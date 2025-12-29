module c3fmt;

enum BraceStyle {
    ALLMAN,
    K_AND_R
}

struct Config {
    bool use_tabs;
    uint tab_size;
    uint indent_width;

    uint max_blank_line_between_statements;
    uint max_line_length;

    BraceStyle brace_style;
    bool else_on_new_line;
}

fn Config default_config()
{
    return {
        .use_tabs = false,
        .tab_size = 4,
        .indent_width = 4,

        .max_blank_line_between_statements = 2,
        .max_line_length = 0,

        .brace_style = ALLMAN,
        .else_on_new_line = true
    };
}