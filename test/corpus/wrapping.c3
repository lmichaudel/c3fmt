fn int main (String a__long__arg, String a__long__arg = "Hello", int a_third_arg = 30) {
    main(a__long__arg: "a very long string that will go after 80 words", a__long__arg: "", 30);
}

fn int Termios.setAttr(&self, Fd fd, Tcactions optional_actions) @deprecated => self.set_attr(fd, optional_actions);