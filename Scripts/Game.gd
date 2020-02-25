extends Node2D

#CA Stuff
const NUMBER_OF_ORIGINS = 10
const ITERATIONS = 2
const GENERATION_WAIT_TIME = 0.5

# Level stuff
const TILE_SIZE = 8
const LEVEL_SIZE = 15 # Levels are square

enum Tile {Wall, Floor, Bumps}
var map = []

onready var tile_map = $TileMap
onready var player = $Player

var playerCoords


##============================================================##
##                                                            ##
##                         Cell Class                         ##
##                                                            ##
##============================================================##
class Cell extends Reference:
	var game
	var x
	var y
	var type
	
	func _init(game, x, y, type):
		self.game = game
		self.x = x
		self.y = y
		self.type = type
	
	func surrounded_by(typeSurroundedBy):
		var count = 0
		var neighbours = get_neighbours()
		for i in range(3):
			for j in range(3):
				if(neighbours[i][j].type == typeSurroundedBy):
					count += 1
		if(neighbours[1][1].type == typeSurroundedBy): count -= 1 # Hack because the centre cell is often treated as floor
		return count == 8
		
	func get_neighbours():
		var neighbours = []
		for iX in range(3):
			neighbours.append([])
			for iY in range(3):
				if(iX*iY == 1):
					neighbours[iX].append(Cell.new(game, x, y, Tile.Wall)) #set the center cell to a wall so that we still have 3 items in that row
				elif(x == 0 and iX == 0 or y == 0 and iY == 0 or x == LEVEL_SIZE-1 and iX == 2 or y == LEVEL_SIZE-1 and iY == 2):
					neighbours[iX].append(Cell.new(game, x-1+iX, y-1+iY, Tile.Wall)) # Here we assume that tiles outside the grid are walls
				else:
					neighbours[iX].append(game.map[x-1+iX][y-1+iY])
		return neighbours
		
	func set_neighbours(tilesToSet, typeToSet):
		for iX in range(3):
			for iY in range(3):
				if(iX*iY == 1):
					continue # skip middle cell
				if(x == 0 and iX == 0 or y == 0 and iY == 0 or x == LEVEL_SIZE-1 and iX == 2 or y == LEVEL_SIZE-1 and iY == 2):
					continue # Can't change cells outside the map
				if(tilesToSet[iX][iY]):
					game.update_cell(x-1+iX, y-1+iY, typeToSet)
	
	func has_neighbour(typeOfNeighbour):
		var count = 0
		var neighbours = get_neighbours()
		for i in range(3):
			for j in range(3):
				if(i*j == 1): continue
				if(neighbours[i][j].type == typeOfNeighbour): return true
		return false


##============================================================##
##                                                            ##
##                      Game functions                        ##
##                                                            ##
##============================================================##
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
			var wallCell = Cell.new(self, x, y, Tile.Wall)
			# Map keeps track of the data
			map[x].append(wallCell)
			# tile_map modifies the game tiles
			tile_map.set_cell(x, y, wallCell.type)
	
	# Set some initial seeds for the automata
	for i in range(NUMBER_OF_ORIGINS):
		var originX = randi() % LEVEL_SIZE
		var originY = randi() % LEVEL_SIZE
		# Do a similar thing as above, but just set a few tiles to floor
		var floorCell = Cell.new(self, originX, originY, Tile.Floor)
		map[originX][originY] = floorCell
		tile_map.set_cell(originX, originY, floorCell.type)
	
	# DO SOME CELLULAR AUTOMATA
	for i in range(ITERATIONS):
		yield(get_tree().create_timer(GENERATION_WAIT_TIME),"timeout")
		for x in range(LEVEL_SIZE):
			for y in range(LEVEL_SIZE):
				apply_rules(map[x][y])
		# copy the tiles into the map array now that all cells have decided their next state
		for x in range(LEVEL_SIZE):
			for y in range(LEVEL_SIZE):
				map[x][y] = Cell.new(self, x, y, tile_map.get_cell(x, y))
	
	# Place the player
	for x in range(LEVEL_SIZE):
		for y in range(LEVEL_SIZE):
			if(map[x][y].type == Tile.Floor):
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

func apply_rules(cell):
	match cell.type:
		
		Tile.Floor:
			# Floor tiles surrounded by walls set most of their neighbours to bumps
			if(cell.surrounded_by(Tile.Wall)):
				var tilesToSet = [
					[true,true,true],
					[true,true,false],
					[true,true,true]
				]
				cell.set_neighbours(tilesToSet, Tile.Bumps)
				
		Tile.Wall:
			# Walls turn into floors when touching bumps
			if(cell.has_neighbour(Tile.Bumps)):
				update_cell(cell.x, cell.y, Tile.Floor)

func update_cell(x, y, type):
	# We don't update any arrays here because we'll do that once all the processing is done by copying the values from the tilemap
	tile_map.set_cell(x, y, type)

# Called every frame. 'delta' is the elapsed time since the previous frame.
#func _process(delta):
#	pass
