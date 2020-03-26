extends Node2D

#CA Stuff
const NUMBER_OF_ORIGINS = 4
const GENERATION_WAIT_TIME = 0.005
const VON_NEUMANN = [
	[0,1,0],
	[1,0,1],
	[0,1,0],
]

# Level stuff
const TILE_SIZE = 8
const LEVEL_SIZE = 15 # Levels are square
const BASE_SHIFTER_COUNT = 3
const BASE_MAX_MANA = 4
const BASE_SPELL_RANGE = 2 #(range of 1 only includes player's current cell)
const ManaUpgradeCost = 2
const RangeUpgradeCost = 1
const LifeUpgradeCost = 5
const ShifterScene = preload("res://Scenes/Shifter.tscn")
const DeathSplash = preload("res://Scenes/DeathSplash.tscn")
const DestroyShifterSplash = preload("res://Scenes/DestroyShifterSplash.tscn")
var LEVEL_NUMBER
var SKULLS
var shifters = []

enum Direction {North, South, East, West}
enum Spell {None, Destroy, Summon, Teleport}
var SpellRange
var mana
var maxMana
enum Tile {Floor, Wall, Pit, HCorridor, VCorridor, Crossroads, Floor1, Floor2, 
		   Faceted, VDoor, VDoorOpen, Ladder, HDoor, HDoorOpen, Pyramid, Backslash,
		   LeverOff, LeverOn, Weird, FilledPit}
const WALKABLES = [Tile.Floor, Tile.HCorridor, Tile.VCorridor, Tile.Crossroads,
				   Tile.Floor1, Tile.Floor2, Tile.VDoorOpen, Tile.Ladder, Tile.HDoorOpen,
				   Tile.Backslash, Tile.FilledPit]
var map = []

onready var tile_map = $TileMap
onready var player = $Player
onready var cursor = $Cursor

var playerCoords
var cursorCoords
var current_spell = Spell.None;

var no_ladders_yet
var no_levers_yet

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
	
	func get_some_neighbours(neighboursToGet):
		var neighbours = []
		for iX in range(3):
			for iY in range(3):
				if(neighboursToGet[iY][iX] != 1):
					continue
				elif(x == 0 and iX == 0 or y == 0 and iY == 0 or x == LEVEL_SIZE-1 and iX == 2 or y == LEVEL_SIZE-1 and iY == 2):
					continue
				else:
					neighbours.append(game.map[x-1+iX][y-1+iY])
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
			var neighboursInDir = self.get_some_neighbours(wallSymmetries[i])
			if(neighboursInDir.size() > 0):
				if(get_some_neighbours(wallSymmetries[i])[0].type == Tile.Pit):
					set_neighbours(wallSymmetries[i], Tile.FilledPit)
					game.SKULLS += 1
					game.shifter_splash(self)
					game.update_skulls()
					game.remove_shifter_from_list(self)
					self.delete()
					return
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
	
	func delete():
		sprite.queue_free()
##============================================================##
##                                                            ##
##                      Game functions                        ##
##                                                            ##
##============================================================##
func _ready():
	#set_process(true)
	OS.set_window_size(Vector2(544, 544))
	OS.set_window_title("Get Blocked!")
	randomize()
	cursor.visible = false;
	cursor.z_index = 10
	maxMana = BASE_MAX_MANA
	SpellRange = BASE_SPELL_RANGE #(range of 1 only includes player's current cell)
	SKULLS = 0
	LEVEL_NUMBER = 0
	build_level()
	$CanvasLayer/Level/LevelValue.text = str(LEVEL_NUMBER)
	$CanvasLayer/Skulls/SkullsValue.text = str(SKULLS)

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
	elif event.is_action("Cancel"):
		finish_spell()
	elif event.is_action("Escape"):
		$CanvasLayer/Escape.visible = true

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
	no_levers_yet = true;
	mana = maxMana
	$CanvasLayer/Mana.rect_size = Vector2(mana*8, 8)
	$CanvasLayer/Level/LevelValue.text = str(LEVEL_NUMBER)
	$CanvasLayer/Skulls/SkullsValue.text = str(SKULLS)
	
	# Clear out shifters, being cautious to call remove on each just cause I don't know exactly how that all works
	for i in range(shifters.size()):
		shifters[i].delete()
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
	for i in range(20):
		yield(get_tree().create_timer(GENERATION_WAIT_TIME),"timeout") # Add a small wait so we can watch it generate
		update_automata_make_halls()
	
	# Make the corners into crossroads
	tile_map.set_cell(0, 0, Tile.Crossroads)
	tile_map.set_cell(0, 14, Tile.Crossroads)
	tile_map.set_cell(14, 0, Tile.Crossroads)
	tile_map.set_cell(14, 14, Tile.Crossroads)
	
	for i in range(15):
		update_automata_lay_carpet()
	
	#yield(get_tree().create_timer(GENERATION_WAIT_TIME*250),"timeout")
	update_automata_spawn_rooms() # Create the holes
	#yield(get_tree().create_timer(GENERATION_WAIT_TIME*250),"timeout")
	update_automata_spawn_rooms() # Surround with tile
	#yield(get_tree().create_timer(GENERATION_WAIT_TIME*250),"timeout")
	update_automata_spawn_rooms() # Fill in surrounding walls
	
	update_automata_add_doors()
	
	update_automata_rotate_doors()
	
	# Spawn shifters
	for i in range(BASE_SHIFTER_COUNT + LEVEL_NUMBER):
		var randX = randi() % LEVEL_SIZE
		var randY = randi() % LEVEL_SIZE
		if(map[randX][randY].type == Tile.Ladder): continue # We don't want to spawn shifters on ladders in case that shifter can't move and thus obscures the ladder forever
		if(shifter_at(randX, randY)): continue # Don't spawn a shifter on top of another one
		if(map[randX][randY].type in WALKABLES):
			shifters.append(Shifter.new(self, randX, randY, randi() % 4))
	
	# Place the player
	for x in range(LEVEL_SIZE):
		for y in range(LEVEL_SIZE):
			if(map[x][y].type == Tile.Floor && !shifter_at(x, y)):
				playerCoords = Vector2(x, y)
	
	# Sanity check - is there a ladder, lever, pit, and shifter?
	var noPits = true
	var noLever = true
	for x in range(LEVEL_SIZE):
		for y in range(LEVEL_SIZE):
			if(map[x][y].type == Tile.Pit):
				noPits = false
			if(map[x][y].type == Tile.LeverOff):
				noLever = false
	if(no_ladders_yet or noPits or noLever or shifters.size() == 0): build_level()
	
	# call_deferred("update_visuals") # Don't want this because it moves shifters before you can move
	player.position = playerCoords * TILE_SIZE # This should achieve the same thing

func update_automata_make_halls():
	for x in range(LEVEL_SIZE):
			for y in range(LEVEL_SIZE):
				apply_hall_rules(map[x][y])
	update_map()

func update_automata_lay_carpet():
	for x in range(LEVEL_SIZE):
			for y in range(LEVEL_SIZE):
				lay_carpet(map[x][y])
	update_map()

func update_automata_spawn_rooms():
	for x in range(LEVEL_SIZE):
			for y in range(LEVEL_SIZE):
				spawn_rooms(map[x][y])
	# copy the tiles into the map array now that all cells have decided their next state
	update_map()

func update_automata_add_doors():
	for x in range(LEVEL_SIZE):
			for y in range(LEVEL_SIZE):
				add_doors(map[x][y])
	update_map()

func update_automata_rotate_doors():
	for x in range(LEVEL_SIZE):
			for y in range(LEVEL_SIZE):
				rotate_doors(map[x][y])
	update_map()

func update_map():
	for x in range(LEVEL_SIZE):
		for y in range(LEVEL_SIZE):
			map[x][y] = Cell.new(self, x, y, tile_map.get_cell(x, y))

func handle_input(input):
	if($CanvasLayer/Upgrade.is_visible_in_tree()):
		return
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
	if(tile_type == Tile.VDoor):
		update_cell(x, y, Tile.VDoorOpen)
	if(tile_type == Tile.HDoor):
		update_cell(x, y, Tile.HDoorOpen)
	if(tile_type == Tile.LeverOff):
		update_cell(x, y, Tile.LeverOn)
		add_ladder()
	call_deferred("update_visuals")

func move_cursor(delta):
	assert(current_spell != Spell.None)
	var x = clamp(cursorCoords.x + delta.x, 0, LEVEL_SIZE-1)
	var y = clamp(cursorCoords.y + delta.y, 0, LEVEL_SIZE-1)
	
	# Doing it this way to ensure that only cardinal directions are allowed
	# While diagonals could be in range, we don't want them so we filter them out as they will not be round numbers like i
	var distanceFromPlayer = Vector2(x, y).distance_to(playerCoords)
	var inRange = false
	for i in range(SpellRange):
		if(distanceFromPlayer == i): inRange = true
		
	if(!inRange): return
	
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
		if(x != playerCoords.x or y != playerCoords.y):
			match spell:
				Spell.Destroy:
					if(map[x][y].type == Tile.VDoor):
						update_cell(x, y, Tile.VDoorOpen)
					elif(map[x][y].type == Tile.HDoor):
						update_cell(x, y, Tile.HDoorOpen)
					elif(!shifter_at(x, y)):
						if(x == playerCoords.x):
							update_cell(x, y, Tile.VDoor)
						else:
							update_cell(x, y, Tile.HDoor)
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
		var weakShifter = weakref(shifter)
		shifter.move();
		if(weakShifter.get_ref()):
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
	if(LEVEL_NUMBER >= 15):
		yield(get_tree().create_timer(0.5),"timeout")
		$CanvasLayer/Win.visible = true
	else:
		$CanvasLayer/Upgrade.visible = true

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

func lay_carpet(cell:Cell):
	var directions = generate_symmetries([[0,1,0],[0,0,0],[0,0,0]])
	match cell.type:
		Tile.Crossroads:
			for i in range(4):
				if( cell.has_neighbour(directions[i], Tile.Floor)):
					cell.set_neighbours(directions[i], Tile.HCorridor if i > 1 else Tile.VCorridor)
		
		Tile.Floor:
			for i in range(2):
				if(cell.has_neighbour(directions[i], Tile.VCorridor)):
					update_cell(cell.x, cell.y, Tile.VCorridor)
			
			for i in range(2, 4):
				if(cell.has_neighbour(directions[i], Tile.HCorridor)):
					update_cell(cell.x, cell.y, Tile.HCorridor)
		
		Tile.VCorridor:
			if(cell.has_neighbour(VON_NEUMANN, Tile.HCorridor)):
				update_cell(cell.x, cell.y, Tile.Crossroads)
		
		Tile.HCorridor:
			if(cell.has_neighbour(VON_NEUMANN, Tile.VCorridor)):
				update_cell(cell.x, cell.y, Tile.Crossroads)

# Gets called 3 times
func spawn_rooms(cell:Cell):
	match cell.type:
		Tile.Floor, Tile.HCorridor, Tile.VCorridor, Tile.Crossroads:
			if(cell.has_only_neighbours([
				[1,1,1],
				[1,0,1],
				[1,0,1]
			], Tile.Wall)):
				cell.set_neighbours([
					[0,1,1],
					[0,1,1],
					[0,1,1]
				], Tile.Backslash)
			
			# TODO: Convert these next two into using the array flipping helpers
			if(cell.has_all_neighbours([
				[1,1,0],
				[1,0,0],
				[1,1,0]
			], Tile.Wall)):
				if(cell.x == 0 or cell.x == LEVEL_SIZE-1):
					update_cell(cell.x, cell.y, Tile.Pit)
				else: 
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
#				if(cell.x == 0 or cell.x == LEVEL_SIZE-1):
				update_cell(cell.x, cell.y, Tile.Pit)
#				else: 
#					update_cell(cell.x, cell.y, Tile.VDoor)
				cell.set_neighbours([
					[0,0,0],
					[0,0,1],
					[0,0,0]
				], Tile.Floor2)
				
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
				], 2, Tile.Faceted)
			
			if(cell.has_neighbour(VON_NEUMANN, Tile.Floor2)):
				update_cell(cell.x, cell.y, Tile.Floor2)
			
			# These next ones are what expand the rooms
			if(cell.has_neighbour(VON_NEUMANN, Tile.Backslash)):
				update_cell(cell.x, cell.y, Tile.Pyramid)
			
			if(cell.has_any_neighbour(Tile.Faceted)):
				update_cell(cell.x, cell.y, Tile.Floor1)
			
			if(cell.has_any_neighbour(Tile.Floor1)):
				update_cell(cell.x, cell.y, Tile.Wall)
				
		Tile.Wall:
			if(cell.has_any_neighbour(Tile.Faceted)):
				update_cell(cell.x, cell.y, Tile.Floor1)
			
			if(cell.has_neighbour(VON_NEUMANN, Tile.Backslash)):
				update_cell(cell.x, cell.y, Tile.Pyramid)
		
#		Tile.Pyramid:
#			var inside = generate_symmetries([[0,1,0],[0,0,0],[0,0,0]])
#			var outside = generate_symmetries([[0,0,0],[0,0,0],[0,1,0]])
#			for i in range(1, 4):
#				if(cell.has_neighbour(inside[i], Tile.Backslash)):
#					cell.set_neighbours(outside[i], Tile.Pyramid)

func add_doors(cell:Cell):
	match cell.type:
		
		Tile.Wall:
			var inside = generate_symmetries([[0,0,0],[0,0,0],[0,1,0]])
			var outside = generate_symmetries([[0,1,0],[0,0,0],[0,0,0]])
			for i in range(4):
				for type in WALKABLES:
					if( cell.has_only_neighbours(outside[i], type) && 
						cell.has_neighbour(inside[i], Tile.Floor1)):
							update_cell(cell.x, cell.y, Tile.VDoor)
		
#		Tile.Floor2:
#			var rowOfThree = generate_symmetries([[1,1,1],[0,0,0],[0,0,0]])
#			for i in range(4):
#				if(cell.has_all_neighbours(rowOfThree[i], Tile.Floor2)):
#					update_cell(cell.x, cell.y, Tile.VDoor)
		Tile.Floor1:
			if(cell.count_all_neighbours(Tile.Faceted) >= 3 and no_ladders_yet):
				# Don't actually update the cell until lever is pressed, just test that
				# a ladder will be able to spawn, so the level will be completable
				no_ladders_yet = false;
				
		Tile.Backslash:
			if(no_levers_yet):
				update_cell(cell.x, cell.y, Tile.LeverOff)
				no_levers_yet = false;
		
		Tile.Pyramid:
			var surrounding = [[0,0,0],[1,0,1],[0,0,0]]
			var below = [[0,0,0],[0,0,0],[0,1,0]]
			if(cell.has_all_neighbours(surrounding, Tile.Pyramid) and
			   cell.has_neighbour(below, Tile.Floor)):
				update_cell(cell.x, cell.y, Tile.VDoor)
		
		Tile.Pit:
			cell.set_neighbours([[0,1,0],[1,0,1],[0,1,0]], Tile.VDoor)
			cell.set_neighbours([[1,0,1],[0,0,0],[1,0,1]], Tile.Weird)

func rotate_doors(cell:Cell):
	match cell.type:
		Tile.VDoor:
			var topAndBottom = [[0,1,0],[0,0,0],[0,1,0]]
			var topAndBottomCells = cell.get_some_neighbours(topAndBottom)
			var leftAndRight = [[0,0,0],[1,0,1],[0,0,0]]
			var leftAndRightCells = cell.get_some_neighbours(leftAndRight)
			var makeHorizontal = true;
			var keepVertical = true;
			for neighbour in topAndBottomCells:
				if(neighbour.type in WALKABLES):
					makeHorizontal = false
			for neighbour in leftAndRightCells:
				if(neighbour.type in WALKABLES):
					keepVertical = false
			if(makeHorizontal && keepVertical):
				update_cell(cell.x, cell.y, Tile.Wall)
			elif(makeHorizontal):
				update_cell(cell.x, cell.y, Tile.HDoor)

func add_ladder():
	var cell
	no_ladders_yet = true
	for x in range(LEVEL_SIZE):
			for y in range(LEVEL_SIZE):
				if(!no_ladders_yet): break
				cell = map[x][y]
				match cell.type:
					Tile.Floor1:
						if(cell.count_all_neighbours(Tile.Faceted) >= 3):
							update_cell(cell.x, cell.y, Tile.Ladder)
							no_ladders_yet = false;
	if(no_ladders_yet): #Then just force one
		update_cell(randi() % LEVEL_SIZE, randi() % LEVEL_SIZE, Tile.Ladder)

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
	
#func destroy_shifters(x, y):
#	var toRemove = []
#	var toDelete = []
#	for i in range(shifters.size()):
#		if(shifters[i].x == x and shifters[i].y == y):
#			toRemove.append(i)
#			toDelete.append(shifters[i])
#	for i in toRemove:
#		shifters.remove(i)
#	for shifter in toDelete:
#		shifter.delete()

func remove_shifter_from_list(toRemove):
	var index = shifters.find(toRemove)
	shifters.remove(index)

func shifter_splash(shifter):
	var destroyShifterSplash = DestroyShifterSplash.instance()
	destroyShifterSplash.position = Vector2(shifter.x*TILE_SIZE, shifter.y*TILE_SIZE)
	self.add_child(destroyShifterSplash)
	yield(get_tree().create_timer(1),"timeout")
	destroyShifterSplash.queue_free()

func update_skulls():
	$CanvasLayer/Skulls/SkullsValue.text = str(SKULLS)

# Called every frame. 'delta' is the elapsed time since the previous frame.
#func _process(delta):
#	pass


func _on_StartButton_pressed():
	LEVEL_NUMBER = 0
	SKULLS = 0
	build_level()
	$CanvasLayer/Win.visible = false
	$CanvasLayer/GameOver.visible = false
	$CanvasLayer/Escape.visible = false
	$CanvasLayer/Home.visible = false
	$CanvasLayer/Upgrade.visible = false


func _on_MenuButton_pressed():
	$CanvasLayer/Win.visible = false
	$CanvasLayer/GameOver.visible = false
	$CanvasLayer/Escape.visible = false
	$CanvasLayer/Home.visible = true
	$CanvasLayer/Upgrade.visible = false

func _on_NoButton_pressed():
	$CanvasLayer/Escape.visible = false


func _on_Continue_pressed():
	build_level()
	$CanvasLayer/Upgrade.visible = false


func _on_UpRange_pressed():
	if(SKULLS >= RangeUpgradeCost):
		SpellRange += 1
		SKULLS -= RangeUpgradeCost
		$CanvasLayer/Skulls/SkullsValue.text = str(SKULLS)


func _on_UpMana_pressed():
	if(SKULLS >= ManaUpgradeCost):
		maxMana += 1
		SKULLS -= ManaUpgradeCost
		$CanvasLayer/Skulls/SkullsValue.text = str(SKULLS)
