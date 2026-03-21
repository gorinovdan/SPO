build:
	cd ./ast && flex -l ./lexer.l
	#cd ./ast && bison -dv -Wcounterexamples ./parser.y
	cd ./ast && bison -dv ./parser.y
	gcc -g -O0 -o ./app ./main.c ./ast/ast_maker.c ./analysis/ir.c ./cfg/cfg.c \
	./codegen/linear_code.c ./ast/parser.tab.c ./ast/lex.yy.c ./ast/ast.c ./view/dgml.c ./view/cfg_dgml.c
	
clean:
	rm ./app

rebuild: clean build

vm-demo: build
	./tools/run_vm.sh ./tests/spo3_demo.txt ./results/output.asm ./results/output.bin

vm-types: build
	./tools/run_vm.sh ./tests/types_demo.txt ./results/types_demo.asm ./results/types_demo.bin

vm-test:
	./tools/run_vm_tests.sh

vm-input: build
	./tools/run_vm.sh ./tests/input.txt ./results/output_input.asm ./results/output_input.bin

inspect-types: vm-types
	python3 ./tools/vm_inspector.py -a ./results/types_demo.asm -b ./results/types_demo.bin -s ./vm/spec.json

remote-types: build
	./app -o ./results/types_demo.asm ./tests/types_demo.txt
	./tools/run_remote.sh ./results/types_demo.asm ../tools/vm_input.txt exec ./results/types_demo.remote.ptptb ./results/types_demo.remote.stdout.txt ./results/types_demo.remote.trace.txt
