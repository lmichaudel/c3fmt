module c3fmt;

enum BraceStyle {
    ALLMAN,
    K_AND_R
}

struct Config {
    bool use_tabs;
    uint tab_size;
    uint indent_width;

    BraceStyle brace_style;
    bool else_on_new_line;
}

fn Config default_config()
{
    return {
        .use_tabs = false,
        .tab_size = 4,
        .indent_width = 4,

        .brace_style = ALLMAN,
        .else_on_new_line = true,
    };
}