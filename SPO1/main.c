#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include "ast/ast_maker.h"
#include "view/dgml.h"

char* filename_from_path(const char* path) {
	// 1. найти последний '/' или '\\' Ч разделитель пути
	const char* lastslash = strrchr(path, '/');
#ifdef _win32
	const char* lastbackslash = strrchr(path, '\\');
	if (lastbackslash && (!lastslash || lastbackslash > lastslash)) {
		lastslash = lastbackslash;
	}
#endif
	// 2. извлечь папку и им€ файла
	if (lastslash) {
		int filename_len = strlen(lastslash + 1) + 1;
		char* filename = malloc(filename_len);
		strncpy(filename, lastslash + 1, filename_len);
		return filename;
	}
	else {
		int filename_len = strlen(path) + 1;
		char* filename = malloc(filename_len);
		strncpy(filename, path, filename_len);
		return filename;
	}
}

int main(int argc, char* argv[]) {


	if (argc < 3) {
		fprintf(stderr, "Using format: %s <input_filenames> <output_dirname>\n", argv[0]);
		return 1;
	}
	const char* output_dir = argv[argc - 1];
	int input_files_count = argc - 2;
	const char** input_files = malloc(input_files_count * sizeof(char*));
	int inputs_counter = 0;
	for (int i = 1; i < argc - 1; i++) {
		input_files[inputs_counter] = argv[i];
		inputs_counter++;
	}

	AST_Wrap** asts = malloc(input_files_count * sizeof(AST_Wrap*));
	for (int i = 0; i < input_files_count; i++) {
		asts[i] = create_ast_wrap(input_files[i]);
		int out_name_sz = snprintf(NULL, 0, "%s/ast.%s.dgml", output_dir, input_files[i]) + 1;
		char* output_ast_filename = malloc(out_name_sz * sizeof(char));
		snprintf(output_ast_filename, out_name_sz, "%s/ast.%s.dgml", output_dir, filename_from_path(input_files[i]));
		export_ast_dgml(asts[i]->ast, output_ast_filename);
		free(output_ast_filename);
	}


	for (int i = 0; i < input_files_count; i++) {
		free_ast_wrap(asts[i]);
	}
	free(asts);
	free(input_files);
	printf("Parsing completed.\n");
	return 0;


	// Place for lab3 step

}