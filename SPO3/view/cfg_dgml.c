#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include "cfg_dgml.h"

typedef struct
{
	void *src;
	void *dst;
	int dashed;
} DgmlLink;

static DgmlLink *links = NULL;
static int link_count = 0;
static int link_capacity = 0;

static void **printed_ir = NULL;
static int printed_ir_count = 0;
static int printed_ir_capacity = 0;

static void links_reset(void)
{
	free(links);
	links = NULL;
	link_count = 0;
	link_capacity = 0;
}

static void printed_ir_reset(void)
{
	free(printed_ir);
	printed_ir = NULL;
	printed_ir_count = 0;
	printed_ir_capacity = 0;
}

static int ptr_list_contains(void **list, int count, const void *p)
{
	for (int i = 0; i < count; i++)
	{
		if (list[i] == p)
			return 1;
	}
	return 0;
}

static void printed_ir_add(void *p)
{
	if (ptr_list_contains(printed_ir, printed_ir_count, p))
		return;
	if (printed_ir_count == printed_ir_capacity)
	{
		int new_cap = printed_ir_capacity ? printed_ir_capacity * 2 : 64;
		void **q = realloc(printed_ir, new_cap * sizeof(void *));
		if (!q)
		{
			perror("realloc");
			exit(EXIT_FAILURE);
		}
		printed_ir = q;
		printed_ir_capacity = new_cap;
	}
	printed_ir[printed_ir_count++] = p;
}

static void add_link(void *src, void *dst, int dashed)
{
	if (!src || !dst)
		return;

	for (int i = 0; i < link_count; i++)
	{
		if (links[i].src == src && links[i].dst == dst && links[i].dashed == dashed)
			return;
	}

	if (link_count == link_capacity)
	{
		int new_cap = link_capacity ? link_capacity * 2 : 128;
		DgmlLink *p = realloc(links, new_cap * sizeof(DgmlLink));
		if (!p)
		{
			perror("realloc");
			exit(EXIT_FAILURE);
		}
		links = p;
		link_capacity = new_cap;
	}
	links[link_count].src = src;
	links[link_count].dst = dst;
	links[link_count].dashed = dashed;
	link_count++;
}

static char *xml_escape(const char *s)
{
	if (!s)
		return strdup("");
	size_t len = 0;
	for (const char *p = s; *p; p++)
	{
		switch (*p)
		{
		case '&':
			len += 5;
			break; /* &amp; */
		case '<':
			len += 4;
			break; /* &lt; */
		case '>':
			len += 4;
			break; /* &gt; */
		case '"':
			len += 6;
			break; /* &quot; */
		case '\'':
			len += 6;
			break; /* &apos; */
		default:
			len += 1;
			break;
		}
	}
	char *out = malloc(len + 1);
	if (!out)
	{
		perror("malloc");
		exit(EXIT_FAILURE);
	}
	char *w = out;
	for (const char *p = s; *p; p++)
	{
		switch (*p)
		{
		case '&':
			memcpy(w, "&amp;", 5);
			w += 5;
			break;
		case '<':
			memcpy(w, "&lt;", 4);
			w += 4;
			break;
		case '>':
			memcpy(w, "&gt;", 4);
			w += 4;
			break;
		case '"':
			memcpy(w, "&quot;", 6);
			w += 6;
			break;
		case '\'':
			memcpy(w, "&apos;", 6);
			w += 6;
			break;
		default:
			*w++ = *p;
			break;
		}
	}
	*w = '\0';
	return out;
}

static char *ir_label(const IRNode *node)
{
	if (!node)
		return strdup("");

	switch (node->type)
	{
	case IR_NODE_CONST:
	{
		char *esc = xml_escape(node->text ? node->text : "");
		int len = snprintf(NULL, 0, "CONST(%s)", esc) + 1;
		char *res = malloc(len);
		snprintf(res, len, "CONST(%s)", esc);
		free(esc);
		return res;
	}
	case IR_NODE_LOAD:
	{
		char *esc = xml_escape(node->text ? node->text : "");
		int len = snprintf(NULL, 0, "LOAD(%s)", esc) + 1;
		char *res = malloc(len);
		snprintf(res, len, "LOAD(%s)", esc);
		free(esc);
		return res;
	}
	case IR_NODE_STORE:
	{
		char *esc = xml_escape(node->text ? node->text : "");
		int len = snprintf(NULL, 0, "STORE(%s)", esc) + 1;
		char *res = malloc(len);
		snprintf(res, len, "STORE(%s)", esc);
		free(esc);
		return res;
	}
	case IR_NODE_CALL:
	{
		char *esc = xml_escape(node->text ? node->text : "");
		int len = snprintf(NULL, 0, "CALL(%s)", esc) + 1;
		char *res = malloc(len);
		snprintf(res, len, "CALL(%s)", esc);
		free(esc);
		return res;
	}
	case IR_NODE_INDEX:
		return strdup("INDEX");
	case IR_NODE_RANGE:
		return strdup("RANGE_OP");
	case IR_NODE_LIST:
		return strdup("LIST");
	case IR_NODE_UNARY:
	case IR_NODE_BINARY:
		return strdup(node->op ? node->op : "");
	case IR_NODE_ERROR:
	default:
		return xml_escape(node->text ? node->text : "");
	}
}

static void print_ir_node(FILE *f, const IRNode *node)
{
	if (!node)
		return;
	if (ptr_list_contains(printed_ir, printed_ir_count, node))
		return;
	printed_ir_add((void *)node);

	char *label = ir_label(node);
	fprintf(f, " <Node Id=\"%p\" Label=\"%s\" Background=\"#FFD580\" />\n", (void *)node, label ? label : "");
	free(label);

	for (int i = 0; i < node->child_count; i++)
	{
		const IRNode *child = node->children[i];
		print_ir_node(f, child);
		add_link((void *)node, (void *)child, 1);
	}
}

static void export_cfg_nodes_with_ir(FILE *f, const CFG_Subprogram *sp)
{
	for (int i = 0; i < sp->cfg.block_count; i++)
	{
		const CFG_Block *b = &sp->cfg.blocks[i];
		if (b->is_circle)
		{
			fprintf(f, " <Node Id=\"%p\" Label=\"\" Shape=\"Circle\" />\n", (void *)b);
		}
		else
		{
			const char *label = b->label ? b->label : "";
			fprintf(f, " <Node Id=\"%p\" Label=\"%s\" />\n", (void *)b, label);
		}
	}

	for (int i = 0; i < sp->cfg.block_count; i++)
	{
		const CFG_Block *b = &sp->cfg.blocks[i];
		if (!b->ir)
			continue;
		print_ir_node(f, b->ir);
		add_link((void *)b, (void *)b->ir, 1);
	}
}

static void export_cfg_links(const CFG_Subprogram *sp)
{
	for (int i = 0; i < sp->cfg.block_count; i++)
	{
		const CFG_Block *b = &sp->cfg.blocks[i];
		if (b->next != -1)
			add_link((void *)b, (void *)&sp->cfg.blocks[b->next], 0);
		if (b->true_next != -1)
			add_link((void *)b, (void *)&sp->cfg.blocks[b->true_next], 0);
		if (b->false_next != -1)
			add_link((void *)b, (void *)&sp->cfg.blocks[b->false_next], 0);
	}
}

void export_cfg_dgml(const CFG_Subprogram *subprogram, const char *filename)
{
	if (!subprogram || !filename)
		return;

	FILE *f = fopen(filename, "w");
	if (!f)
	{
		perror("fopen");
		return;
	}

	links_reset();
	printed_ir_reset();

	fprintf(f, "<?xml version=\"1.0\" encoding=\"utf-8\"?>\n");
	fprintf(f, "<DirectedGraph xmlns=\"http://schemas.microsoft.com/vs/2009/dgml\">\n");
	fprintf(f, " <Nodes>\n");

	export_cfg_nodes_with_ir(f, subprogram);

	fprintf(f, " </Nodes>\n");
	fprintf(f, " <Links>\n");

	export_cfg_links(subprogram);
	for (int i = 0; i < link_count; i++)
	{
		if (links[i].dashed)
		{
			fprintf(f, " <Link Source=\"%p\" Target=\"%p\" StrokeDashArray=\"4, 2\" />\n", links[i].src, links[i].dst);
		}
		else
		{
			fprintf(f, " <Link Source=\"%p\" Target=\"%p\" />\n", links[i].src, links[i].dst);
		}
	}

	fprintf(f, " </Links>\n");
	fprintf(f, "</DirectedGraph>\n");
	fclose(f);

	links_reset();
	printed_ir_reset();
}

void export_cfg_overview_dgml(const CFG_Analysis *analysis, const char *filename)
{
	if (!analysis || !filename)
		return;

	FILE *f = fopen(filename, "w");
	if (!f)
	{
		perror("fopen");
		return;
	}

	fprintf(f, "<?xml version=\"1.0\" encoding=\"utf-8\"?>\n");
	fprintf(f, "<DirectedGraph xmlns=\"http://schemas.microsoft.com/vs/2009/dgml\">\n");
	fprintf(f, " <Nodes>\n");

	for (int si = 0; si < analysis->subprogram_count; si++)
	{
		const CFG_Subprogram *sp = &analysis->subprograms[si];
		for (int bi = 0; bi < sp->cfg.block_count; bi++)
		{
			const CFG_Block *b = &sp->cfg.blocks[bi];

			if (bi == sp->cfg.entry_id)
			{
				fprintf(f, " <Node Id=\"%p\" Label=\"%s\" />\n", (void *)b, sp->name ? sp->name : "");
				continue;
			}
			if (bi == sp->cfg.exit_id)
			{
				fprintf(f, " <Node Id=\"%p\" Label=\"RET\" />\n", (void *)b);
				continue;
			}
			if (b->is_circle)
			{
				fprintf(f, " <Node Id=\"%p\" Label=\"\" Shape=\"Circle\" />\n", (void *)b);
				continue;
			}
			if (b->is_break)
			{
				fprintf(f, " <Node Id=\"%p\" Label=\"BREAK\" />\n", (void *)b);
				continue;
			}
			if (b->true_next != -1 || b->false_next != -1)
			{
				fprintf(f, " <Node Id=\"%p\" Label=\"COND\" />\n", (void *)b);
				continue;
			}
			fprintf(f, " <Node Id=\"%p\" Label=\"ACTION\" />\n", (void *)b);
		}
	}

	fprintf(f, " </Nodes>\n");
	fprintf(f, " <Links>\n");

	for (int si = 0; si < analysis->subprogram_count; si++)
	{
		const CFG_Subprogram *sp = &analysis->subprograms[si];
		for (int bi = 0; bi < sp->cfg.block_count; bi++)
		{
			const CFG_Block *b = &sp->cfg.blocks[bi];
			if (b->next != -1)
				fprintf(f, " <Link Source=\"%p\" Target=\"%p\" />\n", (void *)b, (void *)&sp->cfg.blocks[b->next]);
			if (b->true_next != -1)
				fprintf(f, " <Link Source=\"%p\" Target=\"%p\" />\n", (void *)b, (void *)&sp->cfg.blocks[b->true_next]);
			if (b->false_next != -1)
				fprintf(f, " <Link Source=\"%p\" Target=\"%p\" />\n", (void *)b, (void *)&sp->cfg.blocks[b->false_next]);
		}
	}

	fprintf(f, " </Links>\n");
	fprintf(f, "</DirectedGraph>\n");
	fclose(f);
}

void export_callgraph_dgml(const CallGraph *graph, const char *filename)
{
	if (!graph || !filename)
		return;

	FILE *f = fopen(filename, "w");
	if (!f)
	{
		perror("fopen");
		return;
	}

	fprintf(f, "<?xml version=\"1.0\" encoding=\"utf-8\"?>\n");
	fprintf(f, "<DirectedGraph xmlns=\"http://schemas.microsoft.com/vs/2009/dgml\">\n");
	fprintf(f, " <Nodes>\n");
	for (int i = 0; i < graph->node_count; i++)
	{
		const char *name = graph->node_names[i] ? graph->node_names[i] : "";
		fprintf(f, " <Node Id=\"%s\" Label=\"%s\" />\n", name, name);
	}
	fprintf(f, " </Nodes>\n");

	fprintf(f, " <Links>\n");
	for (int i = 0; i < graph->edge_count; i++)
	{
		int from = graph->edges[i].from;
		int to = graph->edges[i].to;
		if (from < 0 || from >= graph->node_count)
			continue;
		if (to < 0 || to >= graph->node_count)
			continue;
		const char *src = graph->node_names[from];
		const char *dst = graph->node_names[to];
		fprintf(f, " <Link Source=\"%s\" Target=\"%s\" />\n", src ? src : "", dst ? dst : "");
	}
	fprintf(f, " </Links>\n");
	fprintf(f, "</DirectedGraph>\n");
	fclose(f);
}
