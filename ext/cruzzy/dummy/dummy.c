#include <stdlib.h>
#include <stdint.h>

#include <ruby.h>

// https://llvm.org/docs/LibFuzzer.html#toy-example
static int _c_dummy_test_one_input(const uint8_t *data, size_t size)
{
    char test[] = {'a', 'b', 'c'};

    if (size > 0 && data[0] == 'H') {
        if (size > 1 && data[1] == 'I') {
            // This code exists specifically to test the driver and ensure
            // libFuzzer is functioning as expected, so we can safely ignore
            // the warning.
            #pragma clang diagnostic push
            #pragma clang diagnostic ignored "-Warray-bounds"
            test[1024] = 'd';
            #pragma clang diagnostic pop
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
