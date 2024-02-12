#include <dlfcn.h>
#include <stdlib.h>
#include <stdint.h>
#include <stdio.h>
#include <signal.h>
#include <string.h>
#include <unistd.h>

#include <ruby.h>

// 128 arguments should be enough for anybody
#define MAX_ARGS_SIZE 128

int LLVMFuzzerRunDriver(
    int *argc,
    char ***argv,
    int (*cb)(const uint8_t *data, size_t size)
);

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

void Init_cruzzy()
{
    if (signal(SIGINT, sigint_handler) == SIG_ERR) {
        fprintf(stderr, "Could not set SIGINT signal handler\n");
        exit(1);
    }

    VALUE ruzzy = rb_const_get(rb_cObject, rb_intern("Ruzzy"));
    rb_define_module_function(ruzzy, "c_fuzz", &c_fuzz, 2);
    rb_define_module_function(ruzzy, "c_libfuzzer_is_loaded", &c_libfuzzer_is_loaded, 0);
}
