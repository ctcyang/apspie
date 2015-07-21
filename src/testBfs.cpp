﻿#include <deque>

#define MARK_PREDECESSORS 0

// A simple CPU-based reference BFS ranking implementation
template<typename VertexId, typename value>
int SimpleReferenceBfs(
   const VertexId m, const VertexId *h_rowPtrA, const VertexId *h_colIndA,
   value                                   *source_path,
   VertexId                                *predecessor,
   VertexId                                src,
   VertexId                                stop)
{
   //initialize distances
   for (VertexId i = 0; i < m; ++i) {
       source_path[i] = -1;
       if (MARK_PREDECESSORS)
           predecessor[i] = -1;
   }
   source_path[src] = 0;
   VertexId search_depth = 0;

   // Initialize queue for managing previously-discovered nodes
   std::deque<VertexId> frontier;
   frontier.push_back(src);

   //
   //Perform BFS
   //

   CpuTimer cpu_timer;
   cpu_timer.Start();
   while (!frontier.empty()) {
       
       // Dequeue node from frontier
       VertexId dequeued_node = frontier.front();
       frontier.pop_front();
       VertexId neighbor_dist = source_path[dequeued_node] + 1;
       if( neighbor_dist > stop )
           break;

       // Locate adjacency list
       int edges_begin = h_rowPtrA[dequeued_node];
       int edges_end = h_rowPtrA[dequeued_node + 1];

       for (int edge = edges_begin; edge < edges_end; ++edge) {
           //Lookup neighbor and enqueue if undiscovered
           VertexId neighbor = h_colIndA[edge];
           if (source_path[neighbor] == -1) {
               source_path[neighbor] = neighbor_dist;
               if (MARK_PREDECESSORS) {
                   predecessor[neighbor] = dequeued_node;
               }
               if (search_depth < neighbor_dist) {
                   search_depth = neighbor_dist;
               }
               frontier.push_back(neighbor);
           }
       }
   }

   if (MARK_PREDECESSORS)
       predecessor[src] = -1;

   cpu_timer.Stop();
   float elapsed = cpu_timer.ElapsedMillis();
   search_depth++;

   printf("CPU BFS finished in %lf msec. Search depth is: %d\n", elapsed, search_depth);

   return search_depth;
}

template<typename value>
int bfsCPU( const int src, const int m, const int *h_rowPtrA, const int *h_colIndA, value *h_bfsResultCPU, const int stop ) {

   typedef int VertexId; // Use as the node identifier type

   VertexId *reference_check_preds = NULL;

   int depth = SimpleReferenceBfs<VertexId,value>(
       m, h_rowPtrA, h_colIndA,
       h_bfsResultCPU,
       reference_check_preds,
       src,
       stop);

   //print_array(h_bfsResultCPU, m);
   return depth;
}
