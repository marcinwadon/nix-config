{ pkgs, ... }:

pkgs.writeShellScriptBin "clean-bsp-workspace" ''
  rm -rf $PWD/.bloop/
  rm -rf $PWD/.metals/
  rm -rf $PWD/.bsp/
  rm -rf $PWD/.ammonite/
  rm -rf $PWD/.scala-build/
  rm -rf $PWD/project/project/
  rm -rf $PWD/project/target/
  rm -rf $PWD/project/.bloop/
  rm -rf $PWD/target/
  rm -rf $PWD/out/
  rm -f $PWD/project/metals.sbt
''

