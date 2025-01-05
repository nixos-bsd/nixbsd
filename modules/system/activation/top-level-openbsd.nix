{ pkgs, ... }:
{
  config = {
system.activatableSystemBuilderCommands = ''
      mkdir -p $out/bin
      $CC -x c - -o $out/bin/activate-init-native <<EOF
      #include <unistd.h>
      int main(int argc, char** argv, char **envp) {
        setsid();
        setlogin("root");
        execve("${pkgs.runtimeShell}", (char *[]) { "bash", "$out/bin/activate-init", argv[1], NULL }, envp);
        return 123;
      }
      EOF
      substitute ${./activate-init-openbsd.sh} $out/bin/activate-init --subst-var out --subst-var-by runtimeShell ${pkgs.runtimeShell}
    '';
  };
}
