# Profile for the collector-only "monitor" box. Minimal: no git signing, no
# client toolchain extras, and monitorMachine stays null (default) so no hook is
# installed here — this box runs the collector, it doesn't run Claude sessions.
{
  username = "marcin";
  git = {
    userName = "Marcin Wadon";
    userEmail = "marcin.wadon@gmail.com";
  };
}
