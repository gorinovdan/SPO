#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>
#include "ast/ast_maker.h"
#include "cfg/cfg.h"
#include "codegen/linear_code.h"
#include "view/dgml.h"
#include "view/cfg_dgml.h"

#ifdef _WIN32
#define PATH_SEP '\\'
#else
#define PATH_SEP '/'
#endif

char* filename_from_path(const char* path) {
	// 1. найти последний '/' или '\\' — разделитель пути
	const char* lastslash = strrchr(path, '/');
#ifdef _WIN32
	const char* lastbackslash = strrchr(path, '\\');
	if (lastbackslash && (!lastslash || lastbackslash > lastslash)) {
		lastslash = lastbackslash;
	}
#endif
	// 2. извлечь папку и имя файла
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

char* dirname_from_path(const char* path) {
	const char* lastslash = strrchr(path, '/');
#ifdef _WIN32
	const char* lastbackslash = strrchr(path, '\\');
	if (lastbackslash && (!lastslash || lastbackslash > lastslash)) {
		lastslash = lastbackslash;
	}
#endif
	if (!lastslash) {
		char* dir = malloc(2);
		strcpy(dir, ".");
		return dir;
	}
	size_t len = (size_t)(lastslash - path);
	if (len == 0) len = 1; /* корневой каталог */
	char* dir = malloc(len + 1);
	strncpy(dir, path, len);
	dir[len] = '\0';
	return dir;
}

static int is_directory_path(const char* path) {
	struct stat st;
	if (stat(path, &st) != 0) return 0;
#ifdef _WIN32
	return (st.st_mode & _S_IFDIR) != 0;
#else
	return S_ISDIR(st.st_mode);
#endif
}

static void print_usage(const char* prog) {
	fprintf(stderr, "Usage: %s [--cfg] [--cfg-dir <dir>] [-o <output.asm>] <input_files...>\n", prog);
	fprintf(stderr, "  -o, --out       Output assembly listing file (default: output.asm next to first input)\n");
	fprintf(stderr, "  --cfg           Export AST/CFG graphs (optional)\n");
	fprintf(stderr, "  --cfg-dir       Output directory for graphs (default: output file directory)\n");
}

int main(int argc, char* argv[]) {
	if (argc < 2) {
		print_usage(argv[0]);
		return 1;
	}

	const char* output_file = NULL;
	const char* cfg_dir = NULL;
	int emit_cfg = 0;
	const char** input_files = malloc((argc - 1) * sizeof(char*));
	int input_files_count = 0;

	for (int i = 1; i < argc; i++) {
		if ((strcmp(argv[i], "-o") == 0 || strcmp(argv[i], "--out") == 0)) {
			if (i + 1 >= argc) {
				fprintf(stderr, "Missing value for %s\n", argv[i]);
				free(input_files);
				return 1;
			}
			output_file = argv[i + 1];
			i++;
			continue;
		}
		if (strcmp(argv[i], "--cfg") == 0) {
			emit_cfg = 1;
			continue;
		}
		if (strcmp(argv[i], "--cfg-dir") == 0) {
			if (i + 1 >= argc) {
				fprintf(stderr, "Missing value for %s\n", argv[i]);
				free(input_files);
				return 1;
			}
			cfg_dir = argv[i + 1];
			emit_cfg = 1;
			i++;
			continue;
		}
		if ((strcmp(argv[i], "-h") == 0 || strcmp(argv[i], "--help") == 0)) {
			print_usage(argv[0]);
			free(input_files);
			return 0;
		}
		input_files[input_files_count++] = argv[i];
	}

	if (input_files_count < 1) {
		print_usage(argv[0]);
		free(input_files);
		return 1;
	}

	char* output_file_owned = NULL;
	char* cfg_dir_owned = NULL;

	if (output_file && is_directory_path(output_file)) {
		int out_sz = snprintf(NULL, 0, "%s%coutput.asm", output_file, PATH_SEP) + 1;
		output_file_owned = malloc(out_sz);
		snprintf(output_file_owned, out_sz, "%s%coutput.asm", output_file, PATH_SEP);
		output_file = output_file_owned;
	}

	if (!output_file) {
		char* default_dir = dirname_from_path(input_files[0]);
		int out_sz = snprintf(NULL, 0, "%s%coutput.asm", default_dir, PATH_SEP) + 1;
		output_file_owned = malloc(out_sz);
		snprintf(output_file_owned, out_sz, "%s%coutput.asm", default_dir, PATH_SEP);
		output_file = output_file_owned;
		if (emit_cfg && !cfg_dir) {
			cfg_dir_owned = default_dir;
			cfg_dir = cfg_dir_owned;
		}
		else {
			free(default_dir);
		}
	}

	if (emit_cfg && !cfg_dir) {
		cfg_dir_owned = dirname_from_path(output_file);
		cfg_dir = cfg_dir_owned;
	}

	AST_Wrap** asts = malloc(input_files_count * sizeof(AST_Wrap*));
	CFG_InputFile* cfg_files = malloc(input_files_count * sizeof(CFG_InputFile));
	int parsed_files_count = 0;

	for (int i = 0; i < input_files_count; i++) {
		AST_Wrap* wrap = create_ast_wrap(input_files[i]);
		if (!wrap) {
			fprintf(stderr, "Failed to parse file: %s\n", input_files[i]);
			continue;
		}

		if (emit_cfg) {
			/* Экспорт AST по образцу SPO2Denis. */
			char* ast_source_name = filename_from_path(wrap->filename);
			const char* ast_out_dir = cfg_dir;
			char* ast_out_dir_owned = NULL;
			if (!ast_out_dir) {
				ast_out_dir_owned = dirname_from_path(wrap->filename);
				ast_out_dir = ast_out_dir_owned;
			}
			int ast_out_sz = snprintf(NULL, 0, "%s%cast.%s.dgml", ast_out_dir, PATH_SEP, ast_source_name) + 1;
			char* ast_out_path = malloc(ast_out_sz);
			snprintf(ast_out_path, ast_out_sz, "%s%cast.%s.dgml", ast_out_dir, PATH_SEP, ast_source_name);
			export_ast_dgml(wrap->ast, ast_out_path);
			free(ast_out_path);
			free(ast_out_dir_owned);
			free(ast_source_name);
		}

		asts[parsed_files_count] = wrap;
		cfg_files[parsed_files_count].filename = wrap->filename;
		cfg_files[parsed_files_count].parse_tree = wrap->ast;
		parsed_files_count++;
	}

	if (parsed_files_count == 0) {
		fprintf(stderr, "No input files were parsed successfully.\n");
		free(cfg_files);
		free(asts);
		free(input_files);
		return 1;
	}

	CFG_Analysis analysis = cfg_analyze_files(cfg_files, parsed_files_count);

	for (int i = 0; i < analysis.error_count; i++) {
		const CFG_Error* e = &analysis.errors[i];
		fprintf(stderr, "%s:%d:%d: %s\n", e->filename ? e->filename : "<input>", e->line, e->column, e->message ? e->message : "");
	}

	if (emit_cfg) {
		const char* graphs_dir = cfg_dir;
		char* graphs_dir_owned = NULL;
		if (!graphs_dir) {
			graphs_dir_owned = dirname_from_path(cfg_files[0].filename);
			graphs_dir = graphs_dir_owned;
		}

		for (int i = 0; i < analysis.subprogram_count; i++) {
			const CFG_Subprogram* sp = &analysis.subprograms[i];

			char* source_name = filename_from_path(sp->source_filename ? sp->source_filename : "");
			const char* func_out_dir = graphs_dir;
			char* func_out_dir_owned = NULL;
			if (!func_out_dir) {
				func_out_dir_owned = dirname_from_path(sp->source_filename ? sp->source_filename : "");
				func_out_dir = func_out_dir_owned;
			}

			int out_sz = snprintf(NULL, 0, "%s%c%s.%s.dgml", func_out_dir, PATH_SEP, source_name, sp->name) + 1;
			char* out_path = malloc(out_sz);
			snprintf(out_path, out_sz, "%s%c%s.%s.dgml", func_out_dir, PATH_SEP, source_name, sp->name);

			export_cfg_dgml(sp, out_path);

			free(out_path);
			free(func_out_dir_owned);
			free(source_name);
		}

		CallGraph cg = cfg_build_call_graph(&analysis);

		int callgraph_sz = snprintf(NULL, 0, "%s%cfun.calls.graph.dgml", graphs_dir, PATH_SEP) + 1;
		char* callgraph_path = malloc(callgraph_sz);
		snprintf(callgraph_path, callgraph_sz, "%s%cfun.calls.graph.dgml", graphs_dir, PATH_SEP);
		export_callgraph_dgml(&cg, callgraph_path);
		free(callgraph_path);

		int cfg_overview_sz = snprintf(NULL, 0, "%s%ccfg.dgml", graphs_dir, PATH_SEP) + 1;
		char* cfg_overview_path = malloc(cfg_overview_sz);
		snprintf(cfg_overview_path, cfg_overview_sz, "%s%ccfg.dgml", graphs_dir, PATH_SEP);
		export_cfg_overview_dgml(&analysis, cfg_overview_path);
		free(cfg_overview_path);

		cfg_free_call_graph(&cg);
		free(graphs_dir_owned);
	}

	LC_Program program = lc_generate_program(&analysis);
	if (!lc_write_assembly(&program, output_file)) {
		fprintf(stderr, "Failed to write assembly listing: %s\n", output_file ? output_file : "(null)");
	}
	lc_free_program(&program);

	cfg_free_analysis(&analysis);

	for (int i = 0; i < parsed_files_count; i++) {
		free_ast_wrap(asts[i]);
	}
	free(cfg_files);
	free(asts);
	free(input_files);
	free(output_file_owned);
	free(cfg_dir_owned);

	return 0;
}
