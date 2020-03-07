extends Node2D

#CA Stuff
const NUMBER_OF_ORIGINS = 4
const ITERATIONS_PER_LEVEL = [30, 20, 15, 10, 5]
const GENERATION_WAIT_TIME = 0.01
const VON_NEUMANN = [
	[0,1,0],
	[1,0,1],
	[0,1,0],
]

# Level stuff
const TILE_SIZE = 8
const LEVEL_SIZE = 15 # Levels are square
const SHIFTERS_PER_LEVEL = [5, 8, 12, 15, 20]
const ShifterScene = preload("res://Scenes/Shifter.tscn")
const DeathSplash = preload("res://Scenes/DeathSplash.tscn")
var LEVEL_NUMBER = 0
var shifters = []

# Phases of level gen
enum Phase {Halls, SpawnRooms, Doors}
enum Direction {North, South, East, West}
enum Spell {None, Destroy, Summon, Teleport}
var SpellRanges = [0, 1, 1, 2]
var mana
enum Tile {Floor, Wall, Pit, HCorridor, VCorridor, Crossroads, Floor1, Floor2, Faceted, VDoor, VDoorOpen, Ladder}
const WALKABLES = [Tile.Floor, Tile.HCorridor, Tile.VCorridor, Tile.Crossroads, Tile.Floor1, Tile.Floor2, Tile.Ladder]
var map = []

onready var tile_map = $TileMap
onready var player = $Player
onready var cursor = $Cursor

var playerCoords
var cursorCoords
var current_spell = Spell.None;

var no_ladders_yet

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
	
	func set_random_neighbours(possibleCells, howMany, typeToSet):
		var chosenNeighbours = [[0,0,0],[0,0,0],[0,0,0]]
		var cellsChosen = 0
		while(cellsChosen < howMany):
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
	var directionICameFrom # To prevent oscillating in one corridor
	var sprite
	var tween
	
	func _init(game, x, y, direction).(game, x, y, -1):
		self.direction = direction
		tween = Tween.new()
		sprite = ShifterScene.instance()
		sprite.add_child(tween)
		game.add_child(sprite)
		update_visuals()
	
	func move():
		var nextX = x
		var nextY = y
		directionICameFrom = invert_direction(direction)
		var wallSymmetries = game.generate_symmetries([[0,1,0],
													   [0,0,0],
													   [0,0,0]])
		var dirsToCheck = []
		var nextDir = direction
		for i in range(4):
			dirsToCheck.append(nextDir)
			nextDir = rotate_direction_clockwise(nextDir)
		if(dirsToCheck.has(directionICameFrom)):
			dirsToCheck.remove(dirsToCheck.find(directionICameFrom))
			dirsToCheck.append(directionICameFrom) # Just so we check that last
		for i in dirsToCheck:
			if(self.neighbours_are_walkable(wallSymmetries[i]) and !neighbours_are_shifters(wallSymmetries[i])):
				direction = i
				match direction:
					Direction.North:
						nextY = clamp(y-1, 0, LEVEL_SIZE-1)
					Direction.South:
						nextY = clamp(y+1, 0, LEVEL_SIZE-1)
					Direction.West:
						nextX = clamp(x-1, 0, LEVEL_SIZE-1)
					Direction.East:
						nextX = clamp(x+1, 0, LEVEL_SIZE-1)
						
				x = nextX
				y = nextY
				break
	
	func neighbours_are_walkable(candidates):
		var neighbours = get_neighbours()
		for i in range(3):
			for j in range(3):
				if(i*j == 1): continue
				if(candidates[j][i] != 1): continue
				if(!neighbours[i][j].type in WALKABLES): return false
		return true
	
	func neighbours_are_shifters(candidates):
		var neighbours = get_neighbours()
		for i in range(3):
			for j in range(3):
				if(i*j == 1): continue
				if(candidates[j][i] != 1): continue
				for shifter in game.shifters:
					if(shifter.x != i or shifter.y != j): return false
		return true
	
	func update_visuals():
		var newPos = Vector2(x, y) * TILE_SIZE
		tween.interpolate_property(sprite, "position", null, newPos, 0.05, Tween.TRANS_QUAD, 
							  Tween.EASE_IN_OUT)
		tween.start()
		sprite.position = newPos
		
	func rotate_direction_clockwise(direction):
		match direction:
			Direction.North:
				return Direction.East
			Direction.East:
				return Direction.South
			Direction.South:
				return Direction.West
			Direction.West:
				return Direction.North
	
	func invert_direction(direction):
		match direction:
			Direction.North:
				return Direction.South
			Direction.East:
				return Direction.West
			Direction.South:
				return Direction.North
			Direction.West:
				return Direction.East
	
	func remove():
		sprite.queue_free()
##============================================================##
##                                                            ##
##                      Game functions                        ##
##                                                            ##
##============================================================##
func _ready():
	#set_process(true)
	OS.set_window_size(Vector2(544, 544))
	randomize()
	cursor.visible = false;
	cursor.z_index = 10
	build_level()
	$CanvasLayer/Level/LevelValue.text = str(LEVEL_NUMBER)

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

#======================
#                     #
#                     #
#     Build Level     #
#                     #
#                     #
#======================
func build_level():
	map.clear()
	tile_map.clear()
	no_ladders_yet = true;
	mana = 3
	$CanvasLayer/Mana.rect_size = Vector2(mana*8, 8)
		
	
	# Clear out shifters, being cautious to call remove on each just cause I don't know exactly how that all works
	for i in range(shifters.size()):
		shifters[i].remove()
	shifters.clear()
	
	# Make it all walls
	for x in range(LEVEL_SIZE):
		map.append([])
		for y in range(LEVEL_SIZE):
			# Randomly set cells to begin with
			var wallCell = Cell.new(self, x, y, Tile.Wall) if (randi() % 2) else Cell.new(self, x, y, Tile.Floor)
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
	for i in range(ITERATIONS_PER_LEVEL[LEVEL_NUMBER]):
		yield(get_tree().create_timer(GENERATION_WAIT_TIME),"timeout") # Add a small wait so we can watch it generate
		update_automata(Phase.Halls)
	
	#yield(get_tree().create_timer(GENERATION_WAIT_TIME*250),"timeout")
	update_automata(Phase.SpawnRooms) # Create the holes
	#yield(get_tree().create_timer(GENERATION_WAIT_TIME*250),"timeout")
	update_automata(Phase.SpawnRooms) # Surround with tile
	#yield(get_tree().create_timer(GENERATION_WAIT_TIME*250),"timeout")
	update_automata(Phase.SpawnRooms) # Fill in surrounding walls
	
	update_automata(Phase.Doors) # Fill in surrounding walls
	
	# Spawn shifters
	for i in range(SHIFTERS_PER_LEVEL[LEVEL_NUMBER]):
		var randX = randi() % LEVEL_SIZE
		var randY = randi() % LEVEL_SIZE
		if(map[randX][randY].type == Tile.Ladder): continue # We don't want to spawn shifters on ladders in case that shifter can't move and thus obscures the ladder forever
		if(shifter_at(randX, randY)): continue # Don't spawn a shifter on top of another one
		shifters.append(Shifter.new(self, randX, randY, randi() % 4))
	
	# Place the player
	for x in range(LEVEL_SIZE):
		for y in range(LEVEL_SIZE):
			if(map[x][y].type == Tile.Floor && !shifter_at(x, y)):
				playerCoords = Vector2(x, y)
	
	# Sanity check - is there a ladder and at least one pit?
	var noLadder = true;
	var noPit = true;
	for x in range(LEVEL_SIZE):
		for y in range(LEVEL_SIZE):
			if(map[x][y].type == Tile.Ladder):
				noLadder = false;
			if(map[x][y].type == Tile.Pit):
				noPit = false;
				
	if(noLadder or noPit): build_level()
	
	# call_deferred("update_visuals") # Don't want this because it moves shifters before you can move
	player.position = playerCoords * TILE_SIZE # This should achieve the same thing

func update_automata(phase):
	for x in range(LEVEL_SIZE):
			for y in range(LEVEL_SIZE):
				match phase:
					Phase.Halls:
						apply_hall_rules(map[x][y])
					Phase.SpawnRooms:
						spawn_rooms(map[x][y])
					Phase.Doors:
						add_doors(map[x][y])
	# copy the tiles into the map array now that all cells have decided their next state
	update_map()
	
func update_map():
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
	
	# Doing it this way to ensure that only vardinal directions are allowed
	# While diagonals could be in range, we don't want them so we filter them out as they will not be round numbers like i
	var distanceFromPlayer = Vector2(x, y).distance_to(playerCoords)
	var inRange = false
	for i in range(SpellRanges[current_spell]+1):
		print("dist: ", distanceFromPlayer, ", i: ", i)
		if(distanceFromPlayer == i): inRange = true
		
	if(!inRange): return
	
	print("hello?")
	cursorCoords = Vector2(x, y)
	cursor.position = cursorCoords * TILE_SIZE

func handle_cast(spell):
	if(mana <= 0): return
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
	mana -= 1
	$CanvasLayer/Mana.rect_size = Vector2(mana*8, 8)
	cursor.visible = false;

func update_visuals():
		
	player.position = playerCoords * TILE_SIZE
	update_map()
	
	if(map[playerCoords.x][playerCoords.y].type == Tile.Ladder):
		go_to_next_level()
		return
		
	for shifter in shifters:
		shifter.move();
		shifter.update_visuals()
		if(shifter.x == playerCoords.x and shifter.y == playerCoords.y):
			var deathSplash = DeathSplash.instance()
			player.add_child(deathSplash)
			yield(get_tree().create_timer(0.5),"timeout")
			deathSplash.queue_free()
			$CanvasLayer/GameOver.visible = true
	#update_automata()

func update_cell(x, y, type):
	# We don't update any arrays here because we'll do that once all the processing is done by copying the values from the tilemap
	tile_map.set_cell(x, y, type)
	
func go_to_next_level():
	LEVEL_NUMBER += 1
	$CanvasLayer/Level/LevelValue.text = str(LEVEL_NUMBER)
	if(LEVEL_NUMBER >= 5): $CanvasLayer/Win.visible = true
	else: build_level()

#======================
#                     #
#                     #
#       Rules         #
#                     #
#                     #
#======================
func apply_hall_rules(cell:Cell):
	match cell.type:
		# Within each Match, rules at the top have least priority, as any cells
		# modified by rules further down will override changes made by rules further up
		# BUT rules further up do not have the power to affect the CONDITIONS of rules
		# below, because the map is only updated once all next cells have been decided
		Tile.Wall:
			var nearbyWalls = cell.count_all_neighbours(Tile.Wall)
			if(nearbyWalls < 2 or nearbyWalls > 4 ):
				update_cell(cell.x, cell.y, Tile.Floor)
		
		Tile.Floor:
			if(cell.count_all_neighbours(Tile.Wall) == 3):
				update_cell(cell.x, cell.y, Tile.Wall)

# Gets called 3 times
func spawn_rooms(cell:Cell):
	match cell.type:
		Tile.Floor:
			if(cell.has_only_neighbours([
				[1,0,1],
				[1,0,1],
				[1,1,1]
			], Tile.Wall)):
				update_cell(cell.x, cell.y, Tile.Faceted)
				cell.set_random_neighbours([
					[0,1,0],
					[1,0,1],
					[0,1,0]
				], 3, Tile.Faceted)
			
			# TODO: Convert these next two into using the array flipping helpers
			if(cell.has_all_neighbours([
				[1,1,0],
				[1,0,0],
				[1,1,0]
			], Tile.Wall)):
				cell.set_neighbours([
					[0,0,0],
					[1,0,0],
					[0,0,0]
				], Tile.Floor2)
				
			if(cell.has_all_neighbours([
				[0,1,1],
				[0,0,1],
				[0,1,1]
			], Tile.Wall)):
				cell.set_neighbours([
					[0,0,0],
					[0,0,1],
					[0,0,0]
				], Tile.Floor2)
			
			if(cell.has_neighbour(VON_NEUMANN, Tile.Floor2)):
				update_cell(cell.x, cell.y, Tile.Floor2)
				
			if(cell.has_any_neighbour(Tile.Faceted)):
				update_cell(cell.x, cell.y, Tile.Floor1)
			
			if(cell.has_any_neighbour(Tile.Floor1)):
				update_cell(cell.x, cell.y, Tile.Wall)
				
		Tile.Wall:
			if(cell.has_any_neighbour(Tile.Faceted)):
				update_cell(cell.x, cell.y, Tile.Floor1)
		

func add_doors(cell:Cell):
	match cell.type:
		
		Tile.Wall:
			var inside = generate_symmetries([[0,0,0],[0,0,0],[0,1,0]])
			var outside = generate_symmetries([[0,1,0],[0,0,0],[0,0,0]])
			for i in range(4):
				if( cell.has_only_neighbours(outside[i], Tile.Floor) && 
					cell.has_neighbour(inside[i], Tile.Floor1)):
						update_cell(cell.x, cell.y, Tile.VDoor)
		
		Tile.Floor2:
			var rowOfThree = generate_symmetries([[1,1,1],[0,0,0],[0,0,0]])
			for i in range(4):
				if(cell.has_all_neighbours(rowOfThree[i], Tile.Floor2)):
					update_cell(cell.x, cell.y, Tile.Pit)
			
		Tile.Faceted:
			var surrounding = generate_symmetries([[0,0,0],[1,0,1],[0,1,0]])
			for i in range(4):
				if(cell.has_only_neighbours(surrounding[i], Tile.Faceted) and no_ladders_yet):
					update_cell(cell.x, cell.y, Tile.Ladder)
					no_ladders_yet = false;

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


func _on_Button_pressed():
	LEVEL_NUMBER = 0
	build_level()
	$CanvasLayer/Win.visible = false
	$CanvasLayer/GameOver.visible = false
	$CanvasLayer/Home.visible = false
