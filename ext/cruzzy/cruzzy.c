#include <dlfcn.h>
#include <stdlib.h>
#include <stdint.h>
#include <stdio.h>
#include <signal.h>
#include <string.h>
#include <unistd.h>

#include <ruby.h>
#include <ruby/debug.h>

// Internal only: https://github.com/ruby/ruby/blob/v3_3_0/vm_core.h#L2182-L2184
#define RUBY_EVENT_COVERAGE_BRANCH 0x020000

// 128 arguments should be enough for anybody
#define MAX_ARGS_SIZE 128

// TODO: what's a good number here? Should we mmap like Atheris?
#define MAX_COUNTERS 256

extern int LLVMFuzzerRunDriver(
    int *argc,
    char ***argv,
    int (*cb)(const uint8_t *data, size_t size)
);

extern void __sanitizer_cov_8bit_counters_init(uint8_t *start, uint8_t *stop);
extern void __sanitizer_cov_pcs_init(uint8_t *pcs_beg, uint8_t *pcs_end);
extern void __sanitizer_cov_trace_cmp8(uint64_t arg1, uint64_t arg2);
extern void __sanitizer_cov_trace_div8(uint64_t val);

struct PCTableEntry {
  void *pc;
  long flags;
};

struct PCTableEntry PCTABLE[MAX_COUNTERS];
uint8_t COUNTERS[MAX_COUNTERS];
uint32_t COUNTER = 0;
VALUE PROC_HOLDER = Qnil;

static VALUE c_libfuzzer_is_loaded(VALUE self)
{
    void *self_lib = dlopen(NULL, RTLD_LAZY);

    if (!self_lib) {
        return Qfalse;
    }

    void *sym = dlsym(self_lib, "LLVMFuzzerRunDriver");

    dlclose(self_lib);

    return sym ? Qtrue : Qfalse;
}

int ATEXIT_RETCODE = 0;

__attribute__((__noreturn__)) static void ruzzy_exit()
{
     _exit(ATEXIT_RETCODE);
}

__attribute__((__noreturn__)) static void graceful_exit(int code)
{
    // Disable libFuzzer's atexit
    ATEXIT_RETCODE = code;
    atexit(ruzzy_exit);
    exit(code);
}

__attribute__((__noreturn__)) static void sigint_handler(int signal)
{
    fprintf(
        stderr,
        "Signal %d (%s) received. Exiting...\n",
        signal,
        strsignal(signal)
    );
    graceful_exit(signal);
}

static int proc_caller(const uint8_t *data, size_t size)
{
    VALUE arg = rb_str_new((char *)data, size);
    VALUE rb_args = rb_ary_new3(1, arg);
    VALUE result = rb_proc_call(PROC_HOLDER, rb_args);

    // By default, Ruby procs and lambdas will return nil if an explicit return
    // is not specified. Rather than forcing callers to specify a return, let's
    // handle the nil case for them and continue adding the input to the corpus.
    if (NIL_P(result)) {
        // https://llvm.org/docs/LibFuzzer.html#rejecting-unwanted-inputs
        return 0;
    }

    if (!FIXNUM_P(result)) {
        rb_raise(
            rb_eTypeError,
            "fuzz target function did not return an integer or nil"
        );
    }

    return FIX2INT(result);
}

static VALUE c_fuzz(VALUE self, VALUE test_one_input, VALUE args)
{
    char *argv[MAX_ARGS_SIZE];
    int args_len = RARRAY_LEN(args);

    // Assume caller always passes in at least the program name as args[0]
    if (args_len <= 0) {
        rb_raise(
            rb_eRuntimeError,
            "zero arguments passed, we assume at least the program name is present"
        );
    }

    // Account for NULL byte at the end
    if ((args_len + 1) >= MAX_ARGS_SIZE) {
        rb_raise(
            rb_eRuntimeError,
            "cannot specify %d or more arguments",
            MAX_ARGS_SIZE
        );
    }

    if (!rb_obj_is_proc(test_one_input)) {
        rb_raise(rb_eRuntimeError, "expected a proc or lambda");
    }

    PROC_HOLDER = test_one_input;

    for (int i = 0; i < args_len; i++) {
        VALUE arg = RARRAY_PTR(args)[i];
        argv[i] = StringValuePtr(arg);
    }
    argv[args_len] = NULL;

    char **args_ptr = &argv[0];

    // https://llvm.org/docs/LibFuzzer.html#using-libfuzzer-as-a-library
    int result = LLVMFuzzerRunDriver(&args_len, &args_ptr, proc_caller);

    return INT2FIX(result);
}

static VALUE c_trace_cmp8(VALUE self, VALUE arg1, VALUE arg2) {
    // Ruby numerics include both integers and floats. Integers are further
    // divided into fixnums and bignums. Fixnums can be 31-bit or 63-bit
    // integers depending on the bit size of a long. Bignums are arbitrary
    // precision integers. This function can only handle fixnums because
    // sancov only provides comparison tracing up to 8-byte integers.
    if (FIXNUM_P(arg1) && FIXNUM_P(arg2)) {
        long arg1_val = NUM2LONG(arg1);
        long arg2_val = NUM2LONG(arg2);
        __sanitizer_cov_trace_cmp8((uint64_t) arg1_val, (uint64_t) arg2_val);
    }

    return Qnil;
}

static VALUE c_trace_div8(VALUE self, VALUE val) {
    if (FIXNUM_P(val)) {
        long val_val = NUM2LONG(val);
        __sanitizer_cov_trace_div8((uint64_t) val_val);
    }

    return Qnil;
}

static void event_hook_branch(VALUE counter_hash, rb_trace_arg_t *tracearg) {
    VALUE path = rb_tracearg_path(tracearg);
    ID path_sym = rb_intern_str(path);
    VALUE lineno = rb_tracearg_lineno(tracearg);
    VALUE tuple = rb_ary_new_from_args(2, INT2NUM(path_sym), lineno);

    int counter_index;

    if (rb_hash_lookup(counter_hash, tuple) != Qnil) {
        VALUE value = rb_hash_aref(counter_hash, tuple);
        counter_index = FIX2INT(value);
    } else {
        rb_hash_aset(counter_hash, tuple, INT2FIX(COUNTER));
        counter_index = COUNTER;
        COUNTER++;
    }

    COUNTERS[counter_index % MAX_COUNTERS]++;
}

static VALUE c_trace_branch(VALUE self)
{
    VALUE counter_hash = rb_hash_new();

    __sanitizer_cov_8bit_counters_init(COUNTERS, COUNTERS + MAX_COUNTERS);
    __sanitizer_cov_pcs_init((uint8_t *)PCTABLE, (uint8_t *)(PCTABLE + MAX_COUNTERS));

    rb_event_flag_t events = RUBY_EVENT_COVERAGE_BRANCH;
    rb_event_hook_flag_t flags = (
        RUBY_EVENT_HOOK_FLAG_SAFE | RUBY_EVENT_HOOK_FLAG_RAW_ARG
    );
    rb_add_event_hook2(
        (rb_event_hook_func_t) event_hook_branch,
        events,
        counter_hash,
        flags
    );

    // Call Coverage.start(branches: true) to initiate branch hooks
    rb_require("coverage");
    VALUE coverage_mod = rb_const_get(rb_cObject, rb_intern("Coverage"));
    VALUE hash_arg = rb_hash_new();
    rb_hash_aset(hash_arg, ID2SYM(rb_intern("branches")), Qtrue);
    rb_funcall(coverage_mod, rb_intern("start"), 1, hash_arg);

    return Qnil;
}

void Init_cruzzy()
{
    if (signal(SIGINT, sigint_handler) == SIG_ERR) {
        fprintf(stderr, "Could not set SIGINT signal handler\n");
        exit(1);
    }

    VALUE ruzzy = rb_const_get(rb_cObject, rb_intern("Ruzzy"));
    rb_define_module_function(ruzzy, "c_fuzz", &c_fuzz, 2);
    rb_define_module_function(ruzzy, "c_libfuzzer_is_loaded", &c_libfuzzer_is_loaded, 0);
    rb_define_module_function(ruzzy, "c_trace_cmp8", &c_trace_cmp8, 2);
    rb_define_module_function(ruzzy, "c_trace_div8", &c_trace_div8, 1);
    rb_define_module_function(ruzzy, "c_trace_branch", &c_trace_branch, 0);
}
