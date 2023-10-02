tool
extends HBoxContainer

var create_menu

var selected_nodes: Array # of Nodes

func _enter_tree():
	create_menu = $CreateMenu
