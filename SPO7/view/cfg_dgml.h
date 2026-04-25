#ifndef CFG_DGML_H
#define CFG_DGML_H

#include "../cfg/cfg.h"

void export_cfg_dgml(const CFG_Subprogram* subprogram, const char* filename);
void export_cfg_overview_dgml(const CFG_Analysis* analysis, const char* filename);
void export_callgraph_dgml(const CallGraph* graph, const char* filename);

#endif /* CFG_DGML_H */
