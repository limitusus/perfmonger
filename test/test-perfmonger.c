
#include "test.h"
#include <perfmonger.h>


/* global variables */

int argc;
char **argv;

/* utility function proto */

void setup_arguments(const char *arg, ...);

/* test function proto */
void test_parse_args         (void);
void test_parse_args_switches(void);

/* cutter setup/teardown */

void
cut_setup(void)
{
    argc = 0;
    argv = NULL;
}

void
cut_teardown(void)
{
    
}

/* utility function bodies */

void
setup_arguments(const char *arg, ...)
{
    va_list ap;

    argc = 1;
    argv = malloc(sizeof(char *));
    argv[0] = (char *) arg;

    va_start(ap, arg);
    while((arg = va_arg(ap, char *)) != NULL) {
        argv = realloc(argv, sizeof(char *) * (argc + 1));
        argv[argc ++] = (char *) arg;
    }
    va_end(ap);

    cut_take_memory(argv);
}

/* test function bodies */

void
test_parse_args(void)
{
    option_t option;

    setup_arguments("collector", NULL);
    cut_assert_equal_int(0, parse_args(argc, argv, &option));

    /* show help and exit */
    setup_arguments("collector", "-h", NULL);
    cut_assert_equal_int(-1, parse_args(argc, argv, &option));

    /* check -d option and default values */
    setup_arguments("collector", "-d", "/path/to/dev", NULL);
    cut_assert_equal_int(0, parse_args(argc, argv, &option));
    cut_assert_equal_int(1, option.nr_dev);
    cut_assert_equal_string("/path/to/dev", option.dev_list[0]);
    cut_assert_equal_double(1.0, 0.0001, option.interval);
    cut_assert_false(option.report_cpu);
    cut_assert_true(option.report_io);
    cut_assert_false(option.verbose);

    /* with multiple devices */
    setup_arguments("collector", "-d", "/path/to/dev0", "-d", "/path/to/dev1", NULL);
    cut_assert_equal_int(0, parse_args(argc, argv, &option));
    cut_assert_equal_int(2, option.nr_dev);
    cut_assert_equal_string("/path/to/dev0", option.dev_list[0]);
    cut_assert_equal_string("/path/to/dev1", option.dev_list[1]);
    cut_assert_true(option.report_io);

    /* with interval in integer */
    setup_arguments("collector", "-d", "/path/to/dev", "-i", "10", NULL);
    cut_assert_equal_int(0, parse_args(argc, argv, &option));
    cut_assert_equal_double(10.0, 0.0001, option.interval);
    cut_assert_true(option.report_io);

    /* with interval in floating point */
    setup_arguments("collector", "-d", "/path/to/dev", "-i", "0.5", NULL);
    cut_assert_equal_int(0, parse_args(argc, argv, &option));
    cut_assert_equal_double(0.5, 0.0001, option.interval);
    cut_assert_true(option.report_io);

    /* with verbose */
    setup_arguments("collector", "-d", "/path/to/dev", "-v", NULL);
    cut_assert_equal_int(0, parse_args(argc, argv, &option));
    cut_assert_true(option.verbose);
    cut_assert_true(option.report_io);
}

void
test_parse_args_switches(void)
{
    option_t option;

    /* with cpu (default if no device is specified) */
    setup_arguments("collector", NULL);
    cut_assert_equal_int(0, parse_args(argc, argv, &option));
    cut_assert_true (option.report_cpu);
    cut_assert_false(option.report_io);
    cut_assert_false(option.report_ctxsw);

    /* without cpu if some devices are specified */
    setup_arguments("collector", "-d", "/path/to/dev", NULL);
    cut_assert_equal_int(0, parse_args(argc, argv, &option));
    cut_assert_false(option.report_cpu);
    cut_assert_true (option.report_io);
    cut_assert_false(option.report_ctxsw);

    /* with cpu if explicitly specified by -C */
    setup_arguments("collector", "-C", "-d", "/path/to/dev", NULL);
    cut_assert_equal_int(0, parse_args(argc, argv, &option));
    cut_assert_true (option.report_cpu);
    cut_assert_true (option.report_io);
    cut_assert_false(option.report_ctxsw);

    /* without cpu if context switch option is specified */
    setup_arguments("collector", "-S", NULL);
    cut_assert_equal_int(0, parse_args(argc, argv, &option));
    cut_assert_false(option.report_cpu);
    cut_assert_false(option.report_io);
    cut_assert_true (option.report_ctxsw);

    /* with cpu if explicitly specified by -C */
    setup_arguments("collector", "-C", "-S", NULL);
    cut_assert_equal_int(0, parse_args(argc, argv, &option));
    cut_assert_true (option.report_cpu);
    cut_assert_false(option.report_io);
    cut_assert_true (option.report_ctxsw);
}
