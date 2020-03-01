extends Node2D

#CA Stuff
const NUMBER_OF_ORIGINS = 4
const ITERATIONS = 2
const GENERATION_WAIT_TIME = 0.5
const VON_NEUMANN = [
	[0,1,0],
	[1,0,1],
	[0,1,0],
]

# Level stuff
const TILE_SIZE = 8
const LEVEL_SIZE = 15 # Levels are square
const NUMBER_OF_SHIFTERS = 10
const ShifterScene = preload("res://Scenes/Shifter.tscn")
var shifters = []

enum Direction {North, South, West, East}
enum Spell {None, Destroy, Summon, Teleport}
var SpellRanges = [0, 1, 1, 2]
enum Tile {Floor, Wall, Pit, HCorridor, VCorridor, Crossroads}
const WALKABLES = [Tile.Floor, Tile.HCorridor, Tile.VCorridor, Tile.Crossroads]
var map = []

onready var tile_map = $TileMap
onready var player = $Player
onready var cursor = $Cursor

var playerCoords
var cursorCoords
var current_spell = Spell.None;

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
	
	# Neighbour notation:
	# 0 = Don't consider this neighbour
	# 1 = Do consider this neighbour
	func surrounded_by(typeSurroundedBy):
		return has_all_neighbours([
			[1, 1, 1],
			[1, 0, 1],
			[1, 1, 1]
		], typeSurroundedBy)
	
	func count_all_neighbours(typeOfNeighbour):
		return count_neighbours([
			[1, 1, 1],
			[1, 0, 1],
			[1, 1, 1]
		], typeOfNeighbour)
		
	func count_neighbours(neighboursToCheck, typeOfNeighbour):
		var count = 0
		var neighbours = get_neighbours()
		for i in range(3):
			for j in range(3):
				if(i*j == 1): continue
				if(neighboursToCheck[j][i] != 1): continue
				if(neighbours[i][j].type == typeOfNeighbour): count += 1
		return count
	
	# Is at least one neighbour of type 'typeOfNeighbour'
	func has_any_neighbour(typeOfNeighbour):
		return has_neighbour([[1,1,1],[1,0,1],[1,1,1]], typeOfNeighbour)
	
	# Are any of 'neighboursToCheck' of type 'typeOfNeighbour'
	func has_neighbour(neighboursToCheck, typeOfNeighbour):
		var neighbours = get_neighbours()
		for i in range(3):
			for j in range(3):
				if(i*j == 1): continue
				if(neighboursToCheck[j][i] != 1): continue
				if(neighbours[i][j].type == typeOfNeighbour): return true
		return false
	
	# Are all 'neighboursToCheck' of type 'typeOfNeighbour'
	func has_all_neighbours(neighboursToCheck, typeOfNeighbour):
		var neighbours = get_neighbours()
		for i in range(3):
			for j in range(3):
				if(i*j == 1): continue
				if(neighboursToCheck[j][i] != 1): continue
				if(neighbours[i][j].type != typeOfNeighbour): return false
		return true
	
	# Are all 'neighboursToCheck' of type 'typeOfNeighbour',
	# and no other neighbours are of that type
	# Within 'neighboursToCheck' you can specify 'layers' by using different numbers
	# Each layer is checked separately
	func has_only_neighbours(neighboursToCheck, typeOfNeighbour):
		# First, lets find out which 'layers' we're dealing with:
		var layers = []
		for i in range(3):
			for j in range(3):
				var layerIndex = neighboursToCheck[j][i]
				if(!layerIndex in layers):
					layers.append(layerIndex)
					
		var numberOfLayers = layers.size()
		if(0 in layers): numberOfLayers -= 1
		
		# We need at least one layer to succeed
		var failedLayers = 0;
		var neighbours = get_neighbours()
		for layer in layers:
			# We are not interested in cell marked with a zero, so skip this layer
			if(layer == 0): continue
			
			# Keep track of if any cells do not meet the requirements
			var failedCells = 0
			for i in range(3):
				for j in range(3):
					if(i*j == 1): continue # Centre cell
					
					# Make sure all cells *in this layer* are of the right type, and all other cells are not of that type
					if((neighboursToCheck[j][i] == layer and neighbours[i][j].type != typeOfNeighbour) ||
					   (neighboursToCheck[j][i] != layer and neighbours[i][j].type == typeOfNeighbour)): failedCells += 1
			# If any cells failed then this whole layer has failed
			if(failedCells > 0): failedLayers += 1
		
		return failedLayers < numberOfLayers
	
	func set_neighbours(tilesToSet, typeToSet):
		for iX in range(3):
			for iY in range(3):
				# Not skipping the middle cell because we want to be able to set that too
				if(x == 0 and iX == 0 or y == 0 and iY == 0 or x == LEVEL_SIZE-1 and iX == 2 or y == LEVEL_SIZE-1 and iY == 2):
					continue # Can't change cells outside the map
				if(tilesToSet[iY][iX] == 1): # Flip x and y here so that creating the tilesToSet array looks as it does in game
					game.update_cell(x-1+iX, y-1+iY, typeToSet)
	
	func set_random_neighbours(possibleCells, minN, maxN, typeToSet):
		var chosenNeighbours = [[0,0,0],[0,0,0],[0,0,0]]
		var targetN = (randi() % maxN) + minN
		var cellsChosen = 0
		while(cellsChosen < targetN):
			var randomX = randi() % 3
			var randomY = randi() % 3
			if(possibleCells[randomX][randomY] == 1):
				chosenNeighbours[randomX][randomY] = 1
				possibleCells[randomX][randomY] = 0
				cellsChosen += 1
				if(array_is_empty(possibleCells)): break # Attempt to avoid infinite loops
		set_neighbours(chosenNeighbours, typeToSet)
	
	func array_is_empty(array):
		var count = 0;
		for i in range(3):
			count += array[i].count(0)
		return count == 0


##============================================================##
##                                                            ##
##                      Shifter Class                         ##
##                                                            ##
##============================================================##
class Shifter extends Cell:
	var direction
	var sprite
	
	func _init(game, x, y, direction).(game, x, y, -1):
		self.direction = direction
		sprite = ShifterScene.instance()
		game.add_child(sprite)
		update_visuals()
	
	func move():
		var wallSymmetries = game.generate_symmetries([[0,1,0],
													   [0,0,0],
													   [0,0,0]])
			
		if(self.has_neighbour(wallSymmetries[direction], Tile.Floor)):
			var nextX = x
			var nextY = y
			match direction:
				Direction.North:
					nextY = clamp(y-1, 0, LEVEL_SIZE-1)
				Direction.South:
					nextY = clamp(y+1, 0, LEVEL_SIZE-1)
				Direction.West:
					nextX = clamp(x-1, 0, LEVEL_SIZE-1)
				Direction.East:
					nextX = clamp(x+1, 0, LEVEL_SIZE-1)
			if(!game.shifter_at(nextX, nextY)):
				x = nextX
				y = nextY
		else:
			for i in range(4):
				if(self.has_neighbour(wallSymmetries[i], Tile.Floor)):
					direction = i
					break
					
	func update_visuals():
		sprite.position = Vector2(x, y) * TILE_SIZE
	
	func remove():
		sprite.queue_free()
##============================================================##
##                                                            ##
##                      Game functions                        ##
##                                                            ##
##============================================================##
func _ready():
	set_process(true)
	OS.set_window_size(Vector2(480, 480))
	randomize()
	cursor.visible = false;
	cursor.z_index = 10
	build_level()

func _input(event):
	if !event.is_pressed(): 
		return
	if event.is_action("Left"):
		handle_input({"move": Vector2(-1, 0)})
	elif event.is_action("Right"):
		handle_input({"move": Vector2(1, 0)})
	elif event.is_action("Up"):
		handle_input({"move": Vector2(0, -1)})
	elif event.is_action("Down"):
		handle_input({"move": Vector2(0, 1)})
	elif event.is_action("Cast_Destroy"):
		handle_input({"cast": Spell.Destroy})
	elif event.is_action("Cast_Summon"):
		handle_input({"cast": Spell.Summon})
	elif event.is_action("Cast_Teleport"):
		handle_input({"cast": Spell.Teleport})
	elif event.is_action("Cancel"):
		finish_spell()

func build_level():
	#map.clear()
	#tile_map.clear()
	
	# Make it all walls
	for x in range(LEVEL_SIZE):
		map.append([])
		for y in range(LEVEL_SIZE):
			var wallCell = Cell.new(self, x, y, Tile.Wall) if (randi() % 2) else Cell.new(self, x, y, Tile.Crossroads)
			# Map keeps track of the data
			map[x].append(wallCell)
			# tile_map modifies the game tiles
			tile_map.set_cell(x, y, wallCell.type)

	var xQuadrants = [randi() % LEVEL_SIZE/2, (randi() % LEVEL_SIZE/2) + LEVEL_SIZE/2,
					randi() % LEVEL_SIZE/2, (randi() % LEVEL_SIZE/2) + LEVEL_SIZE/2]
	var yQuadrants = [randi() % LEVEL_SIZE/2, randi() % LEVEL_SIZE/2,
					 (randi() % LEVEL_SIZE/2) + LEVEL_SIZE/2, (randi() % LEVEL_SIZE/2) + LEVEL_SIZE/2]
					
	# Set some initial seeds for the automata
	for i in range(NUMBER_OF_ORIGINS):
		var originX = xQuadrants[i]
		var originY = yQuadrants[i]
		# Do a similar thing as above, but just set a few tiles to floor
		var floorCell = Cell.new(self, originX, originY, Tile.Floor)
		map[originX][originY] = floorCell
		tile_map.set_cell(originX, originY, floorCell.type)
	
	# DO SOME CELLULAR AUTOMATA
	for i in range(ITERATIONS):
		yield(get_tree().create_timer(GENERATION_WAIT_TIME),"timeout") # Add a small wait so we can watch it generate
		update_automata()
	
	# Spawn a shifter
	for i in range(NUMBER_OF_SHIFTERS):
		var randX = randi() % LEVEL_SIZE
		var randY = randi() % LEVEL_SIZE
		for shifter in shifters:
			if(shifter.x == randX and shifter.y == randY):
				continue
		shifters.append(Shifter.new(self, randX, randY, randi() % 4))
	
	# Place the player
	for x in range(LEVEL_SIZE):
		for y in range(LEVEL_SIZE):
			if(map[x][y].type == Tile.Floor):
				playerCoords = Vector2(x, y)
	
	call_deferred("update_visuals")

func update_automata():
	for x in range(LEVEL_SIZE):
			for y in range(LEVEL_SIZE):
				apply_rules(map[x][y])
	# copy the tiles into the map array now that all cells have decided their next state
	for x in range(LEVEL_SIZE):
		for y in range(LEVEL_SIZE):
			map[x][y] = Cell.new(self, x, y, tile_map.get_cell(x, y))

func handle_input(input):
	if(input.has("move")):
		if(current_spell != Spell.None):
			move_cursor(input["move"])
		else:
			try_move(input["move"])
	elif(input.has("cast")):
		handle_cast(input["cast"])

func try_move(delta):
	if(playerCoords == null):
		return
	var x = playerCoords.x + delta.x
	var y = playerCoords.y + delta.y
	
	# Don't update ANYTHING if you're trying to move into a shifter
	if(shifter_at(x, y)): return
	
	var tile_type = Tile.Wall
	if x >= 0 && x < LEVEL_SIZE && y >= 0 && y < LEVEL_SIZE:
		tile_type = map[x][y].type
	if(tile_type in WALKABLES):
		playerCoords = Vector2(x, y)
	call_deferred("update_visuals")

func move_cursor(delta):
	assert(current_spell != Spell.None)
	var x = clamp(cursorCoords.x + delta.x, 0, LEVEL_SIZE-1)
	var y = clamp(cursorCoords.y + delta.y, 0, LEVEL_SIZE-1)
	# Constrain to range of spell
	x = clamp(x, playerCoords.x-SpellRanges[current_spell], playerCoords.x+SpellRanges[current_spell])
	y = clamp(y, playerCoords.y-SpellRanges[current_spell], playerCoords.y+SpellRanges[current_spell])
	cursorCoords = Vector2(x, y)
	cursor.position = cursorCoords * TILE_SIZE

func handle_cast(spell):
	if(current_spell != spell):
		current_spell = spell
		start_spell()
	elif(spell != Spell.None):
		var x = cursorCoords.x
		var y = cursorCoords.y
		# Then we must be completing a spell in progress
		match spell:
			Spell.Destroy:
				update_cell(x, y, Tile.Floor)
				if(shifter_at(x, y)):
					destroy_shifters(x, y)
			Spell.Summon:
				if(map[x][y].type in WALKABLES && !shifter_at(x, y)):
					update_cell(x, y, Tile.Wall)
			Spell.Teleport:
				var tile_type = map[x][y].type
				if(!tile_type in WALKABLES || shifter_at(x, y)): return
				playerCoords = Vector2(x, y)
		finish_spell()
		call_deferred("update_visuals")
	
func start_spell():
	cursorCoords = playerCoords
	cursor.position = cursorCoords * TILE_SIZE
	cursor.frame = current_spell-1 # Have to subtract 1 here because the None spell is at index zero
	cursor.visible = true

func finish_spell():
	current_spell = Spell.None
	cursor.visible = false;

func update_visuals():
	player.position = playerCoords * TILE_SIZE
	for shifter in shifters:
		shifter.move();
		shifter.update_visuals()
		if(shifter.x == playerCoords.x and shifter.y == playerCoords.y):
			print("Game over!")
	update_automata()

func update_cell(x, y, type):
	# We don't update any arrays here because we'll do that once all the processing is done by copying the values from the tilemap
	tile_map.set_cell(x, y, type)

func apply_rules(cell):
	match cell.type:
		# Within each Match, rules at the top have least priority, as any cells
		# modified by rules further down will override changes made by rules further up
		
		Tile.Wall:
			if(cell.count_neighbours(VON_NEUMANN, Tile.Wall) > 2 or cell.count_neighbours(VON_NEUMANN, Tile.Floor) > 1):
				update_cell(cell.x, cell.y, Tile.Floor)
		
		Tile.Crossroads:
			if(cell.has_any_neighbour(Tile.Floor) or cell.has_any_neighbour(Tile.Pit)):
				update_cell(cell.x, cell.y, Tile.Pit)
			if(cell.count_neighbours(VON_NEUMANN, Tile.Wall) > 2):
				update_cell(cell.x, cell.y, Tile.Wall)

func flip_array_v(array):
	var tempTop = array.pop_front()
	var tempBot = array.pop_back()
	array.push_front(tempBot)
	array.push_back(tempTop)
	
func flip_array_h(array):
	for row in array:
		var tempTop = row.pop_front()
		var tempBot = row.pop_back()
		row.push_front(tempBot)
		row.push_back(tempTop)

func rotate_array(array):
	var rotated = [[0,0,0],[0,0,0],[0,0,0]]
	for i in range(3):
		for j in range(3):
			rotated[2-j][i] = array[i][j]
	return rotated.duplicate(true)

func generate_symmetries(array):
	var arrayCopy = array.duplicate(true) # leave the original alone
	var symmetries = []
	
	symmetries.append(arrayCopy.duplicate(true))
	flip_array_v(arrayCopy)
	symmetries.append(arrayCopy.duplicate(true))
	
	var rotated = rotate_array(arrayCopy)
	symmetries.append(rotated.duplicate(true))
	flip_array_h(rotated)
	symmetries.append(rotated.duplicate(true))
	
	return symmetries

func shifter_at(x, y):
	for shifter in shifters:
		if(shifter.x == x and shifter.y == y): return true
	return false
	
func destroy_shifters(x, y):
	var toRemove = []
	for i in range(shifters.size()):
		if(shifters[i].x == x and shifters[i].y == y):
			toRemove.append(i)
			shifters[i].remove()
	for i in toRemove:
		shifters.remove(i)
# Called every frame. 'delta' is the elapsed time since the previous frame.
#func _process(delta):
#	pass
