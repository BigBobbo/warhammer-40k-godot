extends Node

var px_per_inch: float = 40.0
var board_width_inches: float = 44.0
var board_height_inches: float = 60.0
var deployment_zone_depth_inches: float = 12.0

func get_board_width_px() -> float:
	return board_width_inches * px_per_inch

func get_board_height_px() -> float:
	return board_height_inches * px_per_inch

func get_deployment_zone_depth_px() -> float:
	return deployment_zone_depth_inches * px_per_inch