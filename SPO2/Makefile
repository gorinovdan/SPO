build:
	cd ./ast && flex -l ./lexer.l
	#cd ./ast && bison -dv -Wcounterexamples ./parser.y
	cd ./ast && bison -dv ./parser.y
	gcc -g -O0 -o ./app ./main.c ./ast/ast_maker.c ./analysis/ir.c ./cfg/cfg.c \
	./ast/parser.tab.c ./ast/lex.yy.c ./ast/ast.c ./view/dgml.c ./view/cfg_dgml.c
	
clean:
	rm ./app

rebuild: clean build
