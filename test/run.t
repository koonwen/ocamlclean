Run bytecode
  $ ocamlrun main.bc
  OK

Size of bytecode
  $ ls -sLh main.bc
  1.2M main.bc

ocamlclean
  $ ocamlclean -verbose main.bc -o main.clean.bc
  Loading `main.bc'... done
  Cleaning code:
    * Pass 1... done
    * Pass 2... done
    * Pass 3... done
    * Pass 4... done
    * Pass 5... done
  Globalising closures... done
  Cleaning environments... done
  Cleaning code:
    * Pass 6... done
    * Pass 7... done
    * Pass 8... done
    * Pass 9... done
    * Pass 10... done
    * Pass 11... done
    * Pass 12... done
  Cleaning primitives... done
  Writting `main.clean.bc'... done
  
  Statistics:
    * Instruction number:    26119  ->    9380   (/2.78)
    * CODE segment length:  119296  ->   43144   (/2.77)
    * Global data number:      304  ->     214   (/1.42)
    * DATA segment length:    4505  ->    1136   (/3.97)
    * Primitive number:        401  ->      40   (/10.03)
    * PRIM segment length:    7870  ->     848   (/9.28)
    * File length:         1169441  ->   47155   (/24.80)

Size of cleaned bytecode
  $ ls -sLh main.clean.bc
  48K main.clean.bc

Run cleaned bytecode
  $ ocamlrun main.clean.bc
  OK
