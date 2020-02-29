extends Node2D

#CA Stuff
const NUMBER_OF_ORIGINS = 4
const ITERATIONS = 10
const GENERATION_WAIT_TIME = 0.5

# Level stuff
const TILE_SIZE = 8
const LEVEL_SIZE = 15 # Levels are square

enum Tile {Floor, Wall, Pit, HCorridor, VCorridor, Crossroads}
var map = []

onready var tile_map = $TileMap
onready var player = $Player

var playerCoords
var playerIsCasting = false;

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
		return has_neighbours([
			[1, 1, 1],
			[1, 0, 1],
			[1, 1, 1]
		], typeSurroundedBy)
	
	# Is at least one neighbour of type 'typeOfNeighbour'
	func has_any_neighbour(typeOfNeighbour):
		return has_neighbour([[1,1,1],[1,0,1],[1,1,1]], typeOfNeighbour)
	
	func has_neighbour(neighboursToCheck, typeOfNeighbour):
		var count = 0
		var neighbours = get_neighbours()
		for i in range(3):
			for j in range(3):
				if(i*j == 1): continue
				if(neighboursToCheck[j][i] != 1): continue
				if(neighbours[i][j].type == typeOfNeighbour): return true
		return false
	
	# Are all 'neighboursToCheck' of type 'typeOfNeighbour'
	func has_neighbours(neighboursToCheck, typeOfNeighbour):
		var count = 0
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
		handle_input({"move": Vector2(-1, 0)})
	elif event.is_action("Right"):
		handle_input({"move": Vector2(1, 0)})
	elif event.is_action("Up"):
		handle_input({"move": Vector2(0, -1)})
	elif event.is_action("Down"):
		handle_input({"move": Vector2(0, 1)})
	elif event.is_action("Cast_Destroy"):
		handle_input({"cast": "destroy"})

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
	if(playerIsCasting):
		start_cast(input)
	elif(input.move):
		try_move(input["move"])

func try_move(delta):
	if(playerCoords == null):
		return
	var x = playerCoords.x + delta.x 
	var y = playerCoords.y + delta.y
	var tile_type = Tile.Wall
	if x >= 0 && x < LEVEL_SIZE && y >= 0 && y < LEVEL_SIZE:
		tile_type = map[x][y].type
	match tile_type:
		Tile.Floor, Tile.HCorridor, Tile.VCorridor, Tile.Crossroads:
			playerCoords = Vector2(x, y)
	call_deferred("update_visuals")

func start_cast(inp):
	pass
	
func start_cast_destroy():
	pass

func update_visuals():
	player.position = playerCoords * TILE_SIZE

func update_cell(x, y, type):
	# We don't update any arrays here because we'll do that once all the processing is done by copying the values from the tilemap
	tile_map.set_cell(x, y, type)

func apply_rules(cell):
	match cell.type:
		# Within each Match, rules at the top have least priority, as any cells
		# modified by rules further down will override changes made by rules further up
		
		Tile.Floor:
			# Floors become horizontal corridoors when there are walls above and below
			if(cell.has_neighbours([
				[0,1,0],
				[0,0,0],
				[0,1,0]
			], Tile.Wall)):
				update_cell(cell.x, cell.y, Tile.HCorridor)
			
			# Floors become vertical corridoors when there are walls on left and right
			if(cell.has_neighbours([
				[0,0,0],
				[1,0,1],
				[0,0,0]
			], Tile.Wall)):
				update_cell(cell.x, cell.y, Tile.VCorridor)
				
			# Floor tiles surrounded by walls generate pits (has priority over previous two rules so is placed after them)
			if(cell.surrounded_by(Tile.Wall)):
				cell.set_neighbours([
					[0,0,0],
					[0,1,0],
					[0,0,0]
				], Tile.Pit)
				cell.set_random_neighbours([
					[0,1,0],
					[1,0,1],
					[0,1,0]
				], 2, 2, Tile.Pit)
			
			var wallSymmetries = generate_symmetries([[1,1,1],
													  [0,0,0],
													  [0,0,0]])
													
			var pitSymmetries = generate_symmetries([[0,0,0],
													 [0,0,0],
													 [0,1,0]])
												
			var floorSymmetries = generate_symmetries([[0,1,0],
													   [0,0,0],
													   [0,0,0]])
			for i in range(4):
				if( cell.has_only_neighbours(wallSymmetries[i], Tile.Wall) && 
					cell.has_only_neighbours(pitSymmetries[i], Tile.Pit)):
						cell.set_neighbours(floorSymmetries[i], Tile.Floor)
				
		Tile.Wall:
			# Walls turn into floors when touching pits
			if(cell.has_any_neighbour(Tile.Pit)):
				update_cell(cell.x, cell.y, Tile.Floor)
			
			# Walls adjacent to corridors in the right orientation turn into corridoors
			if(cell.has_only_neighbours([
				[0,0,0],
				[1,0,2],
				[0,0,0]
			], Tile.HCorridor)):
				update_cell(cell.x, cell.y, Tile.HCorridor)
			
			# Walls adjacent to corridors in the right orientation turn into corridoors
			if(cell.has_only_neighbours([
				[0,1,0],
				[0,0,0],
				[0,2,0]
			], Tile.VCorridor)):
				update_cell(cell.x, cell.y, Tile.VCorridor)
		
		Tile.VCorridor:
			# Corridoors become crossroads when meeting corridoors of the other orientation
			if(cell.has_neighbour([
				[0,0,0],
				[1,0,1],
				[0,0,0]
			], Tile.HCorridor)):
				update_cell(cell.x, cell.y, Tile.Crossroads)
		
		Tile.HCorridor:
			# Corridoors become crossroads when meeting corridoors of the other orientation
			if(cell.has_neighbour([
				[0,1,0],
				[0,0,0],
				[0,1,0]
			], Tile.VCorridor)):
				update_cell(cell.x, cell.y, Tile.Crossroads)

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


# Called every frame. 'delta' is the elapsed time since the previous frame.
#func _process(delta):
#	pass
