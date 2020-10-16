Normal compilation

  $ $LABRYS build-program Hello
  Compiling Hello
  Linking Hello
  $ $LABRYS build-program Fact
  Compiling Fact
  Compiling Nat
  Linking Fact
  $ $LABRYS build-program TailFact
  Compiling TailFact
  Linking TailFact
  $ $LABRYS build-program NativeFact
  Compiling NativeFact
  Linking NativeFact
  $ $LABRYS build-program PolyFact
  Compiling PolyFact
  Linking PolyFact

Test compiling printed LLVM-IR code

  $ $LABRYS print-early-llvm Hello | if [ $LLVM_VERSION ]; then llc-$LLVM_VERSION - -o /dev/null; fi
  Linking Hello
  $ $LABRYS print-early-llvm Fact | if [ $LLVM_VERSION ]; then llc-$LLVM_VERSION - -o /dev/null; fi
  Linking Fact
  $ $LABRYS print-early-llvm TailFact | if [ $LLVM_VERSION ]; then llc-$LLVM_VERSION - -o /dev/null; fi
  Linking TailFact
  $ $LABRYS print-early-llvm NativeFact | if [ $LLVM_VERSION ]; then llc-$LLVM_VERSION - -o /dev/null; fi
  Linking NativeFact
  $ $LABRYS print-early-llvm PolyFact | if [ $LLVM_VERSION ]; then llc-$LLVM_VERSION - -o /dev/null; fi
  Linking PolyFact

Test behaviours

  $ $LABRYS build-program Hello
  Linking Hello
  $ ./a.out
  Hello World !
  $ $LABRYS build-program Fact
  Linking Fact
  $ valgrind ./a.out
  1
  1
  2
  6
  24
  120
  40320
  $ $LABRYS build-program TailFact
  Linking TailFact
  $ valgrind ./a.out
  1
  1
  2
  6
  24
  120
  720
  5040
  40320
  $ $LABRYS build-program NativeFact
  Linking NativeFact
  $ valgrind ./a.out
  1
  1
  2
  6
  24
  120
  5040
  40320
  $ $LABRYS build-program PolyFact
  Linking PolyFact
  $ valgrind ./a.out
  1
  1
  2
  6
  24
  720
  5040
  40320
