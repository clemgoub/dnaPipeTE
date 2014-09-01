import os, sys, math
import networkx as nx
import matplotlib.pyplot as plt
from collections import Counter
%matplotlib inline 

binFolder = '/home/clement/pbil-pandata/Papier_ET_albo/albo1.19_2x10X/chrysalis'
binIndexFile = '/home/clement/pbil-pandata/Papier_ET_albo/albo1.19_2x10X/chrysalis'
binIndex = dict([(line.strip().split('\t')[0],line.strip().split('\t')[1].split('/')[-2]) for line in open(binIndexFile)])

def graphComp(cid, w, h):
    """
    cid = component id
    w = width of the output
    h = height of the output
    """
    prepath = binFolder + binIndex[str(cid)] + '/'
    graphData = [x.split() for x in open(prepath + 'c' + str(cid) + '.graph.out').read().strip().split('\n')[1:]]
    graph = nx.Graph()

    for item in graphData:
        current = item[0]
        seq = item[-2]
        graph.add_node(current, seq = seq, color='green', size=min(int(item[2]) * 10,1000))
    graph.add_node('-1',seq = '', color='red', size = 1000)

    for item in graphData:
        graph.add_edge(item[1],item[0])
    plt.figure(figsize=[w,h])
    nx.draw_graphviz(graph, prog='sfdp',
                     node_size = [graph.node[n]['size'] for n in graph.nodes()],
                     node_color = [graph.node[n]['color'] for n in graph.nodes()])
    
def networkComp(cid, w, h):
    """
    cid = component id
    w = width of the output
    h = height of the output
    """
    prepath = binFolder + binIndex[str(cid)] + '/'
    graphData = [x.split() for x in open(prepath + 'c' + str(cid) + '.graph.out').read().strip().split('\n')[1:]]
    graph = nx.MultiDiGraph()
    
    #iterate through graph once to get all essential nodes
    path = []
    nodes = []
    for item in graphData:
        current = item[0]
        prev = item[1]
        seq = item[-2]
        
        if len(path) == 0:
            path = [prev, current]
        else:
            if path[-1] == prev:
                path.append(current)
            else:
                nodes.append(path[0])
                nodes.append(path[-1])
                path = [prev, current]
    
    nodes.append(path[0])
    nodes.append(path[-1])
    
    #get essential nodes from probable path file
    probPaths = [[node.split(':')[0] for node in line.split('path=')[-1][1:-1].split()]\
                  for line in open(prepath + 'c' + str(cid) + '.graph.allProbPaths.fasta').read().strip().split('\n') \
                  if line[0] == '>']
    nodes.extend(sum(probPaths,[]))
    nodes = list(set(nodes))
    #iterate through again to connect essential nodes
    path = []
    for item in graphData:
        current = item[0]
        prev = item[1]
        seq = item[-2]
        
        if len(path) == 0:
            path = [prev, current]
        else:
            if path[-1] == prev:
                path.append(current)
            else:
                addPath = []
                for node in path:
                    if node in nodes:
                        addPath.append(node)
                graph.add_path(addPath)
                path = [prev, current]
    addPath = []
    for node in path:
        if node in nodes:
            addPath.append(node)
    graph.add_path(addPath)
    
    plt.figure(figsize=[w,h])
    plt.axis('off')
    plt.rcParams['text.usetex'] = False
    pos = nx.graphviz_layout(graph,prog='sfdp')

    nx.draw_networkx_edges(graph,pos,width=1, alpha=0.8)
    nx.draw_networkx_labels(graph,pos)
    colors = ['red','blue','green','purple','black','yellow'] * 10
    
    print 'Number of probable paths: ', len(probPaths)
    for y, probPath in enumerate(probPaths):
        edgelist = [('-1',probPath[0])]
        for i in range(0,len(probPath) - 1, 1):
            if probPath[i] in graph.nodes() and probPath[i+1] in graph.nodes():
                shortest = nx.shortest_path(graph, probPath[i],probPath[i+1])
                [edgelist.append((shortest[a],shortest[a+1])) for a in range(0,len(shortest) - 1, 1)]
        edgelist.append((probPath[-1],graph.neighbors(probPath[-1])[0]))
        nodeList = sum(edgelist,())
        edgePos = []
        for k,v in pos.items():
            if k != '-1' and k in nodeList:
                if graph.node[k].has_key('path'):
                    edgePos.append((k, (v[0], graph.node[k]['path'] + 2)))
                else:
                    edgePos.append((k, (v[0], v[1])))
                    graph.node[k]['path'] = v[1] + 2
            if k == '-1':
                edgePos.append(('-1',(pos['-1'][0],pos['-1'][1])))
        edgePos = dict(edgePos)
        nx.draw_networkx_edges(graph,edgePos,edgelist = edgelist, width = 3, alpha=0.2,edge_color=colors.pop())

networkComp('4511', 20, 10)
graphComp('4511', 20, 10)