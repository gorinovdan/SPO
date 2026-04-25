#include <stdio.h>
#include <stdlib.h>
#include "dgml.h"

int node_id_counter = 0;

typedef struct {
	void* src;
	void* dst;
	int is_dash;
} Link;

static Link* links = NULL;
static int links_count = 0;
static int links_capacity = 0;

static void add_link(void* src, void* dst, int is_dash) {
	if (links_count == links_capacity) {
		int new_cap = links_capacity ? links_capacity * 2 : 64;
		Link* p = realloc(links, new_cap * sizeof(Link));
		if (!p) {
			perror("realloc");
			exit(EXIT_FAILURE);
		}
		links = p;
		links_capacity = new_cap;
	}
	links[links_count].src = src;
	links[links_count].dst = dst;
	links[links_count].is_dash = is_dash;
	links_count++;
}

/* Print a node and return its ID; collect links for later printing */
static void* print_node(FILE* f, AST_Node* node) {
	int id = node_id_counter++;

	switch (node->type) {
	case AST_TYPE_STRING:
	case AST_TYPE_BOOL:
	case AST_TYPE_INT:
	case AST_TYPE_UINT:
	case AST_TYPE_LONG:
	case AST_TYPE_ULONG:
	case AST_TYPE_BYTE:
	case AST_TYPE_CHAR: {
		fprintf(f, " <Node Id=\"%p\" Label=\"%s: %s\" Background=\"#ABC48A\" />\n", (void*)node, ast_node_names[node->type], node->type_name);
		break;
	}
	case AST_ID: {
		fprintf(f, " <Node Id=\"%p\" Label=\"%s: %s\" Background=\"#ABC48A\" />\n", (void*)node, ast_node_names[node->type], node->id);
		break;
	}
	case AST_STRING: {
		fprintf(f, " <Node Id=\"%p\" Label=\"%s: %s\" Background=\"#ABC48A\" />\n", (void*)node, ast_node_names[node->type], node->string_value);
		break;
	}
	case AST_CHAR: {
		fprintf(f, " <Node Id=\"%p\" Label=\"%s: %c\" Background=\"#ABC48A\" />\n", (void*)node, ast_node_names[node->type], node->char_value);
		break;
	}
	case AST_HEX:
	case AST_BIT:
	case AST_BOOL:
	case AST_NUM: {
		fprintf(f, " <Node Id=\"%p\" Label=\"%s: %u\" Background=\"#ABC48A\" />\n", (void*)node, ast_node_names[node->type], node->num_val);
		break;
	}
	case AST_TYPE_ARRAY_DIMENTION: {
		fprintf(f, " <Node Id=\"%p\" Label=\"%s: %d\" Background=\"#ABC48A\" />\n", (void*)node, ast_node_names[node->type], node->arr_dimention);
		break;
	}
	default: {
		fprintf(f, " <Node Id=\"%p\" Label=\"%s\" Background=\"#ABC48A\" />\n", (void*)node, ast_node_names[node->type]);

		for (int i = 0; i < node->compound.child_count; i++) {
			void* child_id = print_node(f, node->compound.children[i]);
			add_link((void*)node, child_id, 0);
		}

		break;
	}
	}

	return (void*)node;
}

void export_ast_dgml(AST_Node* root, const char* filename) {
	FILE* f = fopen(filename, "w");
	if (!f) {
		perror("fopen");
		return;
	}
	fprintf(f, "<?xml version=\"1.0\" encoding=\"utf-8\"?>\n");
	fprintf(f, "<DirectedGraph xmlns=\"http://schemas.microsoft.com/vs/2009/dgml\">\n");
	/* print nodes first */
	fprintf(f, " <Nodes>\n");
	node_id_counter = 0;
	links_count = 0; /* reset collected links */
	print_node(f, root);
	fprintf(f, " </Nodes>\n");
	/* then print links collected during traversal */
	fprintf(f, " <Links>\n");
	for (int i = 0; i < links_count; i++) {
		fprintf(f, " <Link Source=\"%p\" Target=\"%p\" />\n", links[i].src, links[i].dst);
	}
	fprintf(f, " </Links>\n");
	fprintf(f, "</DirectedGraph>\n");
	fclose(f);
	/* free link storage */
	free(links);
	links = NULL;
	links_capacity = 0;
	links_count = 0;
}
