#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include "../core/graph.h"
#include <valgrind/callgrind.h>
#include "../core/contraction.h"
#include "../core/fibheap.h"

//This should leak memory
int main() {
    
    int MAX_IMPORT = 100;
    
    Graph* gg = gNew();

    //Load up edges
    FILE* fp = fopen("map.csv", "r");
    char via[20];
    char from[20];
    char to[20];
    double length;
    int i=0;
    while( !feof( fp ) && i < MAX_IMPORT ){
        i++;
        
        fscanf(fp, "%[^,],%[^,],%[^,],%lf\n", &via, &from, &to, &length);
        
        gAddVertex( gg, from );
        gAddVertex( gg, to );
        
        Street* s1 = streetNew( via, length );
        gAddEdge(gg, from, to, (EdgePayload*)s1);
        Street* s2 = streetNew( via, length );
        gAddEdge(gg, to, from, (EdgePayload*)s2);
    }
    fclose( fp );
    
    WalkOptions* wo = woNew();
    fibheap* pq = init_priority_queue( gg, wo, 1 );
    
    while( !fibheap_empty(pq) ) {
        Vertex* next = pqPop( pq );
        printf( "next vertex: %p\n", next );
    }
    
    fibheap_delete( pq );
    woDestroy( wo );
    gDestroy(gg);
    
    return 1;
} 
