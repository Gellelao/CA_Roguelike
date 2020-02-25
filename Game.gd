extends Node2D

const TILE_SIZE = 8
const LEVEL_SIZE = 15 # Width and height, levels are square

#CA Stuff
const ORIGINS = 10
const ITERATIONS = 2
const GENERATION_WAIT_TIME = 0.05

enum Tile {Wall, Floor, Bumps}

var map = []

onready var tile_map = $TileMap
onready var player = $Player

var playerCoords

# Called when the node enters the scene tree for the first time.
func _ready():
	set_process(true)
	OS.set_window_size(Vector2(480, 480))
	randomize()
	build_level()
	
func _input(event):
	if !event.is_pressed(): 
		return
	if event.is_action("Left"):
		try_move(-1, 0)
	elif event.is_action("Right"):
		try_move(1, 0)
	elif event.is_action("Up"):
		try_move(0, -1)
	elif event.is_action("Down"):
		try_move(0, 1)
	
func build_level():
	map.clear()
	tile_map.clear()
	
	# Make it all walls
	for x in range(LEVEL_SIZE):
		map.append([])
		for y in range(LEVEL_SIZE):
			# Can't use our set_cell() helper because we're initializing it here (and don't want to have to wait for all these cells to get set anyway)
			map[x].append(Tile.Wall)
			tile_map.set_cell(x, y, Tile.Wall)
	
	# Set some initial seeds for the automata
	for i in range(ORIGINS):
		var originX = randi() % LEVEL_SIZE
		var originY = randi() % LEVEL_SIZE
		# THESE NEXT TWO LINES GOTTA HAVE THE SAME TILE TYPE, I TRIED PUTTING IT IN A FUNCTION TO AVOID THE NEED FOR THIS COMMENT BUT THIS IS REALLY THE ONLY TIME THIS OCCURS AND IT FELT NOT VERY NECESSARY?
		map[originX][originY] = Tile.Floor
		tile_map.set_cell(originX, originY, Tile.Floor)
	
	# DO SOME CELLULAR AUTOMATA
	for i in range(ITERATIONS):
		yield(get_tree().create_timer(GENERATION_WAIT_TIME),"timeout")
		for x in range(LEVEL_SIZE):
			for y in range(LEVEL_SIZE):
				print("checkin ", x, ", ", y)
				apply_rules(x, y)
		# copy the tiles into the map array now that all cells have decided their next state
		for x in range(LEVEL_SIZE):
			for y in range(LEVEL_SIZE):
				map[x][y] = tile_map.get_cell(x, y)
		
		
	
	# Place the player
	for x in range(LEVEL_SIZE):
			for y in range(LEVEL_SIZE):
				if(map[x][y] == Tile.Floor):
					playerCoords = Vector2(x, y)
	
	call_deferred("update_visuals")
	
func try_move(dx, dy):
	var x = playerCoords.x + dx 
	var y = playerCoords.y + dy
	var tile_type = Tile.Wall
	if x >= 0 && x < LEVEL_SIZE && y >= 0 && y < LEVEL_SIZE:
		tile_type = map[x][y]
	match tile_type:
		Tile.Floor:
			playerCoords = Vector2(x, y)
	call_deferred("update_visuals")
	
func update_visuals():
	player.position = playerCoords * TILE_SIZE

func apply_rules(x, y):
	# Floor tiles surrounded by walls set most of their neighbours to bumps
	if(map[x][y] == Tile.Floor and surrounded_by(x, y, Tile.Wall)):
		var tilesToSet = [
			[true,true,true],
			[true,true,false],
			[true,true,true]
		]
		set_neighbours(x, y, tilesToSet, Tile.Bumps)
	
	# Walls turn into floors when touching bumps
	if(map[x][y] == Tile.Wall and has_neighbour(x, y, Tile.Bumps)):
		update_cell(x, y, Tile.Floor)

func surrounded_by(x, y, type):
	var count = 0
	var neighbours = get_neighbours(x, y)
	for i in range(3):
		count += neighbours[i].count(type)
	if(neighbours[1][1] == type): count -= 1 # Hack because the centre cell is often treated as floor
	return count == 8
	
func has_neighbour(x, y, type):
	var count = 0
	var neighbours = get_neighbours(x, y)
	for i in range(3):
		count += neighbours[i].count(type)
	if(neighbours[1][1] == type): count -= 1 # Hack because the centre cell is often treated as floor
	return count > 0

func get_neighbours(x, y):
	var neighbours = []
	for iX in range(3):
		neighbours.append([])
		for iY in range(3):
			if(iX*iY == 1):
				neighbours[iX].append(Tile.Wall)
				continue # set the center cell to a wall so that we still have 3 items in that row
			if(x == 0 and iX == 0 or y == 0 and iY == 0 or x == LEVEL_SIZE-1 and iX == 2 or y == LEVEL_SIZE-1 and iY == 2):
				neighbours[iX].append(Tile.Wall) # Here we assume that tiles outside the grid are walls
			else:
				neighbours[iX].append(map[x-1+iX][y-1+iY])
	return neighbours

func set_neighbours(x, y, tilesToSet, type):
	print("setting neihgbours for ", x, ", ", y)
	for iX in range(3):
		for iY in range(3):
			if(iX*iY == 1):
				continue # skip middle cell
			if(x == 0 and iX == 0 or y == 0 and iY == 0 or x == LEVEL_SIZE-1 and iX == 2 or y == LEVEL_SIZE-1 and iY == 2):
				continue # Can't change cells outside the map
			if(tilesToSet[iX][iY]):
				update_cell(x-1+iX, y-1+iY, type)
			
func update_cell(x, y, type):
	print("setting cell for ", x, ", ", y)
	# We don't update any arrays here because we'll do that once all the processing is done by copying the values from the tilemap
	tile_map.set_cell(x, y, type)

# Called every frame. 'delta' is the elapsed time since the previous frame.
#func _process(delta):
#	pass
