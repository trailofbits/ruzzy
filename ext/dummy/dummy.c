#include <stdlib.h>
#include <stdint.h>

#include <ruby.h>

// https://llvm.org/docs/LibFuzzer.html#toy-example
static int _c_dummy_test_one_input(const uint8_t *data, size_t size)
{
    volatile char boom = 'x';
    char test[] = {'a', 'b', 'c'};

    if (size == 2) {
        if (data[0] == 'H') {
            if (data[1] == 'I') {
                // Intentional heap-use-after-free for testing purposes
                char * volatile ptr = malloc(128);
                ptr[0] = 'x';
                free(ptr);
                boom = ptr[0];
                (void) boom;
            }
        }
    }

    return 0;
}

static VALUE c_dummy_test_one_input(VALUE self, VALUE data)
{
    int result = _c_dummy_test_one_input(
        (uint8_t *)RSTRING_PTR(data),
        RSTRING_LEN(data)
    );

    return INT2NUM(result);
}

void Init_dummy()
{
    VALUE ruzzy = rb_const_get(rb_cObject, rb_intern("Ruzzy"));
    rb_define_module_function(ruzzy, "c_dummy_test_one_input", &c_dummy_test_one_input, 1);
}
