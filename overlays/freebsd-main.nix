final: prev: {
  freebsd = prev.freebsd.override {
    branch = "main";
  };
}
