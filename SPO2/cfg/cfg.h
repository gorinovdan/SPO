#ifndef CFG_H
#define CFG_H

#include "../analysis/ir.h"

typedef struct CFG_Error {
	char* filename;
	int line;
	int column;
	char* message;
} CFG_Error;

typedef struct CFG_Block {
	int id;

	int next;       /* unconditional successor, -1 if none */
	int true_next;  /* conditional successor (true), -1 if none */
	int false_next; /* conditional successor (false), -1 if none */

	char* label;   /* label for CFG node (XML-escaped where needed) */
	IRNode* ir;    /* operation tree root (optional) */
	int is_circle; /* render as circle node */
	int is_break;  /* render as BREAK node */
} CFG_Block;

typedef struct CFG_Graph {
	CFG_Block* blocks;
	int block_count;
	int block_capacity;

	int entry_id;
	int exit_id;
} CFG_Graph;

typedef struct CFG_Subprogram {
	char* name;
	char* signature;
	char* source_filename;
	CFG_Graph cfg;
} CFG_Subprogram;

typedef struct CFG_Analysis {
	CFG_Subprogram* subprograms;
	int subprogram_count;
	int subprogram_capacity;

	CFG_Error* errors;
	int error_count;
	int error_capacity;
} CFG_Analysis;

typedef struct CFG_InputFile {
	const char* filename;
	AST_Node* parse_tree;
} CFG_InputFile;

typedef struct CallGraph_Edge {
	int from;
	int to;
} CallGraph_Edge;

typedef struct CallGraph {
	char** node_names;
	int node_count;
	int node_capacity;

	CallGraph_Edge* edges;
	int edge_count;
	int edge_capacity;
} CallGraph;

CFG_Analysis cfg_analyze_files(const CFG_InputFile* files, int file_count);
void cfg_free_analysis(CFG_Analysis* analysis);

CallGraph cfg_build_call_graph(const CFG_Analysis* analysis);
void cfg_free_call_graph(CallGraph* graph);

#endif /* CFG_H */
