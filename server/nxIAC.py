import networkx as nx
import matplotlib.pyplot as plt
from graphviz import Source

# ill move over to pygraphviz later, pydot will work for my needs now
import warnings
warnings.filterwarnings("ignore", category=DeprecationWarning) 

class nxIAC(nx.DiGraph):
    # ----------------------------- Super class stuff ---------------------------- #
    # all_edge_dict = {"color": "blue"}
    # all_node_dict = {"color": "blue"}
    all_edge_dict = {}
    all_node_dict = {}
    edge_attr_dict_factory = lambda self: self.all_edge_dict
    node_attr_dict_factory = lambda self: self.all_node_dict
    def __init__(self, incoming_graph_data=None,node_attr=None,edge_attr=None, **attr):
        # pass to super
        super(nxIAC, self).__init__(incoming_graph_data, **attr)
        if node_attr is not None:
            self.all_node_dict = node_attr
        if edge_attr is not None:
            self.all_edge_dict = edge_attr

    # ----------------------------- IAC stuff ---------------------------- #
    def renderIACGraph(self,filename):
        newGraph = nxIAC(edge_attr={"dir": "back"})
        newGraph.add_nodes_from(self.nodes(data=True))
        newGraph.add_edges_from(self.edges(data=True))
        newGraph=newGraph.reverse()
        newGraphSource=Source(source=nx.nx_pydot.to_pydot(newGraph).to_string(),format='png',filename=filename)
        newGraphSource.render()
    
    def renderSVG(self):
        newGraph = nxIAC(edge_attr={"dir": "back"})
        newGraph.add_nodes_from(self.nodes(data=True))
        newGraph.add_edges_from(self.edges(data=True))
        newGraph=newGraph.reverse()
        newGraphSource=Source(source=nx.nx_pydot.to_pydot(newGraph).to_string(),format='svg')
        return newGraphSource.pipe().decode('utf-8')
        
