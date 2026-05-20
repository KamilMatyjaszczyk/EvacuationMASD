model Evac

global {

	file buildings_file <- file("../includes/parcdeforum/buildingrotated.shp");
	file exits_file <- file("../includes/parcdeforum/building2.shp");
	file boundary_file <- file("../includes/parcdeforum/boundaryrotated.shp");

	geometry shape <- envelope(boundary_file);
	geometry festival_area;

	int nb_guests <- 180;
	int nb_guards <- 20;
	int nb_people <- nb_guests + nb_guards;
	int nb_initial_fires <- 1;
	int guard_no_guest_cycles_before_exit <- 20;

	float people_speed <- 15.0;
	float danger_distance <- 200.0;
	float fire_spread_proba <- 0.01;
	float guest_exit_detection_distance <- 45.0;
	float guard_instruction_distance <- 45.0;
	float guard_vision_distance <- 80.0;
	float guest_wander_speed <- 8.0;
	float guard_patrol_speed <- 10.0;
	float wander_target_distance <- 40.0;
	float exit_fire_danger_distance <- 90.0;

	// BDI predicates
	predicate exitKnown <- new_predicate("exitKnown");
	predicate evacuate <- new_predicate("evacuate");
	predicate guideGuests <- new_predicate("guideGuests");
	predicate waitForGuidance <- new_predicate("waitForGuidance");
	predicate guardDoneGuiding <- new_predicate("guardDoneGuiding");
	predicate patrolling <- new_predicate("patrolling");
	predicate fireDanger <- new_predicate("fireDanger");
	predicate panicking <- new_predicate("panicking");
	predicate fleeFire <- new_predicate("fleeFire");
	predicate gregarism <- new_predicate("gregarism");

	init {
		write "===== INIT STARTED =====";

		festival_area <- geometry(boundary_file);

		create festival_boundary from: boundary_file;

		write "Boundary agents created: " + length(festival_boundary);

		create building from: buildings_file {
			flammable <- int(read("flamable")) = 1;
			walkable_building <- int(read("walkable")) = 1;
		}

		write "Buildings created: " + length(building);
		write "Flammable buildings: " + length(building where each.flammable);
		write "Walkable buildings: " + length(building where each.walkable_building);
		write "Blocking buildings: " + length(building where !each.walkable_building);

		create evac_exit from: exits_file {
			name <- string(read("name"));
			is_open <- int(read("open")) = 1;
		}

		write "Exits created: " + length(evac_exit);
		write "Open exits: " + length(evac_exit where each.is_open);

		// Reset grid
		ask evac_cell {
			inside_boundary <- false;
			blocked_by_building <- false;
			walkable <- false;
			can_spawn <- false;
		}

		// Først: merk celler som overlapper boundary
		ask festival_boundary {
			geometry boundary_shape <- self.shape;

			ask evac_cell overlapping boundary_shape {
				inside_boundary <- true;
			}
		}

		// Så: merk celler som overlapper ikke-walkable buildings
		ask building where (!each.walkable_building) {
			geometry building_shape <- self.shape;

			ask evac_cell overlapping building_shape {
				blocked_by_building <- true;
			}
		}

		// Walkable = inni boundary og ikke blokkert av building
		ask evac_cell {
			walkable <- inside_boundary and !blocked_by_building;
		}

		// Spawn-celler: bare walkable celler som ikke er helt alene
		ask evac_cell where each.walkable {
			if length(self neighbors_at(1) where each.walkable) >= 2 {
				can_spawn <- true;
			}
		}

		write "Grid prepared.";
		write "Grid cells: " + length(evac_cell);
		write "Inside boundary cells: " + length(evac_cell where each.inside_boundary);
		write "Walkable cells: " + length(evac_cell where each.walkable);
		write "Spawn cells: " + length(evac_cell where each.can_spawn);
		write "Blocked building cells: " + length(evac_cell where each.blocked_by_building);

		// Starter brann i tilfeldige flammable buildings
		if !empty(building where each.flammable) {
			ask min([nb_initial_fires, length(building where each.flammable)]) among (building where each.flammable) {
				on_fire <- true;
			}
		} else {
			write "WARNING: No flammable buildings found. Check field name: flamable";
		}

		write "Initial fires: " + length(building where each.on_fire);

		create person number: nb_guests {
			role <- "guest";
			do init_person;
		}

		// Lager vakter
		create person number: nb_guards {
			role <- "guard";
			do init_person;
		}

		write "People created: " + length(person);
		write "People with target: " + length(person where each.target_cell != nil);
		write "===== INIT FINISHED =====";
	}

	reflex update_fire {
		ask building where each.on_fire {
			building burning_building <- self;

			ask building where (
				each.flammable
				and !each.on_fire
				and (each.location distance_to burning_building.location < danger_distance)
			) {
				if flip(fire_spread_proba) {
					on_fire <- true;
				}
			}
		}
	}

	reflex debug_cycles when: every(10#cycle) {
		write "Cycle: " + cycle
			+ " | People remaining: " + length(person)
			+ " | Buildings on fire: " + length(building where each.on_fire)
			+ " | Walkable cells: " + length(evac_cell where each.walkable);
	}

	reflex stop_sim when: empty(person) {
		write "All people evacuated. Simulation stopped.";
		do pause;
	}
}

species festival_boundary {

	aspect default {
		draw shape color: #white border: #black;
	}
}

grid evac_cell width: 60 height: 60 neighbors: 8 optimizer: "A*" {

	bool inside_boundary <- false;
	bool blocked_by_building <- false;
	bool walkable <- false;
	bool can_spawn <- false;

	aspect default {
		if can_spawn {
			draw shape color: #lightgreen border: #lightgray;
		} else if walkable {
			draw shape color: rgb(230, 230, 230) border: #lightgray;
		} else if blocked_by_building {
			draw shape color: rgb(80, 80, 80) border: #darkgray;
		} else {
			draw shape color: rgb(245, 245, 245) border: #lightgray;
		}
	}
}

species building {

	bool flammable <- false;
	bool walkable_building <- false;
	bool on_fire <- false;

	aspect default {
		if on_fire {
			draw shape color: #red border: #black;
		} else if walkable_building {
			draw shape color: #lightgray border: #gray;
		} else if flammable {
			draw shape color: #orange border: #black;
		} else {
			draw shape color: #darkgray border: #black;
		}
	}
}

species evac_exit {

	string name <- "exit";
	bool is_open <- true;

	aspect default {
		if is_open {
			draw circle(12) color: #green border: #black;
		} else {
			draw circle(12) color: #red border: #black;
		}
	}
}

species person skills: [moving] control: simple_bdi {
	//role
	string role <- "guest";

	//exit related
	evac_exit target_exit <- nil;
	evac_cell target_cell <- nil;
	evac_cell wander_cell <- nil;
	

	bool knows_exit <- false;
	bool evacuated <- false;

	int cycles_without_guest_seen <- 0;
	bool guard_can_evacuate <- false;
	
	//panic related
	float panic <- 0.0;
	float max_panic <- 1.0;
	float panic_increase_distance <- 180.0;
	float panic_decay <- 0.005;
	float panic_speed_bonus <- 12.0;
	float panic_threshold <- 0.6;
	bool has_fire_danger_belief <- false;
	bool has_panicking_belief <- false;
	float flee_target_distance <- 70.0;
	
	//gregarism
	float crowd_vision_distance <- 45.0;
	person crowd_leader <- nil;
	bool has_crowd_belief <- false;
	evac_exit crowd_target_exit <- nil;
	evac_cell crowd_target_cell <- nil;

	action init_person {
		list<evac_cell> spawn_cells <- evac_cell where each.can_spawn;

		if empty(spawn_cells) {
			spawn_cells <- evac_cell where each.walkable;
		}

		if !empty(spawn_cells) {
			evac_cell start_cell <- one_of(spawn_cells);
			location <- start_cell.location;
		} else {
			write "ERROR: No walkable spawn cells found.";
			do die;
		}

		if role = "guard" {
			do learn_nearest_exit;
			do add_desire(predicate: guideGuests, strength: 1.0);
		} else {
			do add_desire(predicate: waitForGuidance, strength: 1.0);
		}
	}

	action learn_nearest_exit {
	if !empty(evac_exit where each.is_open) and !empty(evac_cell where each.walkable) {
		list<evac_exit> open_exits <- evac_exit where each.is_open;
		list<building> burning_buildings <- building where each.on_fire;
		list<evac_exit> safe_exits <- [];

		if !empty(burning_buildings) {
			loop ex over: open_exits {
				float nearest_fire_distance <- min(burning_buildings collect (each.location distance_to ex.location));

				if nearest_fire_distance > exit_fire_danger_distance {
					safe_exits <- safe_exits + ex;
				}
			}
		} else {
			safe_exits <- open_exits;
		}

		if !empty(safe_exits) {
			target_exit <- safe_exits closest_to self.location;
		} else {
			target_exit <- open_exits closest_to self.location;
		}

		target_cell <- (evac_cell where each.walkable) closest_to target_exit.location;

		knows_exit <- true;
		wander_cell <- nil;

		do add_belief(exitKnown);
	}
}

	action receive_exit_information_from_guard {
		do learn_nearest_exit;
	}

	action choose_new_wander_cell {
		point current_location <- self.location;

		list<evac_cell> possible_cells <- evac_cell where (
			each.walkable
			and (each.location distance_to current_location < wander_target_distance)
			and (each.location distance_to current_location > 5.0)
		);

		if empty(possible_cells) {
			possible_cells <- evac_cell where each.walkable;
		}

		if !empty(possible_cells) {
			wander_cell <- one_of(possible_cells);
		}
	}

	action wander_randomly(float wander_speed) {
		if wander_cell = nil {
			do choose_new_wander_cell;
		}

		if wander_cell != nil {
			do goto target: wander_cell.location
				on: (evac_cell where each.walkable)
				speed: wander_speed
				recompute_path: true;

			if self.location distance_to wander_cell.location < 5.0 {
				wander_cell <- nil;
			}
		}
	}
	action choose_flee_cell {
		list<building> burning_buildings <- building where each.on_fire;
	
		if !empty(burning_buildings) {
			building nearest_fire <- burning_buildings closest_to self.location;
			point fire_location <- nearest_fire.location;
			float current_fire_distance <- self.location distance_to fire_location;
	
			list<evac_cell> possible_cells <- evac_cell where (
				each.walkable
				and (each.location distance_to self.location < flee_target_distance)
				and (each.location distance_to fire_location > current_fire_distance)
			);
	
			if empty(possible_cells) {
				possible_cells <- evac_cell where each.walkable;
			}
	
			if !empty(possible_cells) {
				wander_cell <- possible_cells farthest_to fire_location;
			}
		}
	}

	action flee_from_fire {
	if wander_cell = nil {
		do choose_flee_cell;
	}

	if wander_cell != nil {
		float flee_speed <- guest_wander_speed + panic * panic_speed_bonus;

		do goto target: wander_cell.location
			on: (evac_cell where each.walkable)
			speed: flee_speed
			recompute_path: true;

		if self.location distance_to wander_cell.location < 5.0 {
			wander_cell <- nil;
		}
	}
	}
	
	action inform_nearby_guests {
		point guard_location <- self.location;

		ask person where (
			each.role = "guest"
			and !each.evacuated
			and !each.knows_exit
			and (each.location distance_to guard_location < guard_instruction_distance)
		) {
			do receive_exit_information_from_guard;
		}
	}

	action check_visible_guests {
		point guard_location <- self.location;

		int visible_guests <- length(person where (
			each.role = "guest"
			and !each.evacuated
			and (each.location distance_to guard_location < guard_vision_distance)
		));

		if visible_guests > 0 {
			cycles_without_guest_seen <- 0;
		} else {
			cycles_without_guest_seen <- cycles_without_guest_seen + 1;
		}

		if cycles_without_guest_seen >= guard_no_guest_cycles_before_exit {
			guard_can_evacuate <- true;
			wander_cell <- nil;

			do add_belief(guardDoneGuiding);
		}
	}
	
	action move_to_target_exit {
		if target_cell != nil {
			float current_speed <- people_speed;
	
			if role = "guest" {
				current_speed <- people_speed + panic * panic_speed_bonus;
			}
	
			do goto target: target_cell.location
				on: (evac_cell where each.walkable)
				speed: current_speed
				recompute_path: true;
	
			if target_exit != nil and self.location distance_to target_exit.location < 18.0 {
				evacuated <- true;
				do die;
			} else if self.location distance_to target_cell.location < 12.0 {
				evacuated <- true;
				do die;
			}
		}
	}

	action follow_crowd {
		if crowd_leader = nil or dead(crowd_leader) {
			if crowd_target_exit != nil and crowd_target_cell != nil {
				target_exit <- crowd_target_exit;
				target_cell <- crowd_target_cell;
				knows_exit <- true;
				wander_cell <- nil;
				crowd_leader <- nil;
				has_crowd_belief <- false;
	
				do add_belief(exitKnown);
			} else {
				crowd_leader <- nil;
				has_crowd_belief <- false;
				wander_cell <- nil;
			}
		} else {
			float follow_speed <- guest_wander_speed + panic * panic_speed_bonus;
	
			do goto target: crowd_leader.location
				on: (evac_cell where each.walkable)
				speed: follow_speed
				recompute_path: true;
	
			if crowd_leader.knows_exit and (self.location distance_to crowd_leader.location < 10.0) {
				target_exit <- crowd_leader.target_exit;
				target_cell <- crowd_leader.target_cell;
				knows_exit <- true;
				wander_cell <- nil;
				crowd_leader <- nil;
				has_crowd_belief <- false;
	
				do add_belief(exitKnown);
			}
		}
	}
		
	reflex guest_perceive_evacuating_crowd
	when: role = "guest" and !evacuated and !knows_exit {
		point guest_location <- self.location;
	
		list<person> visible_evacuating_guests <- person where (
			each.role = "guest"
			and !each.evacuated
			and each.knows_exit
			and each.target_cell != nil
			and (each.location distance_to guest_location < crowd_vision_distance)
		);
	
		if !empty(visible_evacuating_guests) {
			crowd_leader <- visible_evacuating_guests closest_to self.location;
			crowd_target_exit <- crowd_leader.target_exit;
			crowd_target_cell <- crowd_leader.target_cell;
	
			if !has_crowd_belief {
				do add_belief(gregarism);
				has_crowd_belief <- true;
			}
		}
	}
	
	reflex guest_reconsider_exit_if_dangerous
		when: role = "guest" and !evacuated and knows_exit and target_exit != nil {
			list<building> burning_buildings <- building where each.on_fire;
		
			if !empty(burning_buildings) {
				float nearest_fire_distance <- min(burning_buildings collect (each.location distance_to target_exit.location));
		
				if nearest_fire_distance < exit_fire_danger_distance {
					knows_exit <- false;
					target_exit <- nil;
					target_cell <- nil;
					wander_cell <- nil;
		
					do remove_belief(exitKnown);
					do remove_desire(evacuate);
					do remove_intention(evacuate);
		
					do add_belief(fireDanger);
					do add_desire(predicate: fleeFire, strength: 1.0);
				}
			}
		}
				 	
	reflex guest_perceive_fire_danger
	when: role = "guest" and !evacuated
	 {
		list<building> burning_buildings <- building where each.on_fire;
	
		if !empty(burning_buildings) {
			building nearest_fire <- burning_buildings closest_to self.location;
			float distance_to_fire <- self.location distance_to nearest_fire.location;
	
			if distance_to_fire < panic_increase_distance {
				float panic_gain <- (panic_increase_distance - distance_to_fire) / panic_increase_distance;
				panic <- min([max_panic, panic + panic_gain * 0.03]);
	
				if !has_fire_danger_belief {
					do add_belief(fireDanger);
					has_fire_danger_belief <- true;
				}
			} else {
				panic <- max([0.0, panic - panic_decay]);
			}
	
			if panic >= panic_threshold and !has_panicking_belief {
				do add_belief(panicking);
				has_panicking_belief <- true;
			}
		} else {
			panic <- max([0.0, panic - panic_decay]);
		}
	}

	reflex guest_perceive_exit_when_near
	when: role = "guest" and !evacuated and !knows_exit {
		point guest_location <- self.location;
	
		list<evac_exit> visible_exits <- evac_exit where (
			each.is_open
			and (each.location distance_to guest_location < guest_exit_detection_distance)
		);
	
		if !empty(visible_exits) {
			list<building> burning_buildings <- building where each.on_fire;
			list<evac_exit> safe_visible_exits <- [];
	
			if !empty(burning_buildings) {
				loop ex over: visible_exits {
					float nearest_fire_distance <- min(burning_buildings collect (each.location distance_to ex.location));
	
					if nearest_fire_distance > exit_fire_danger_distance {
						safe_visible_exits <- safe_visible_exits + ex;
					}
				}
			} else {
				safe_visible_exits <- visible_exits;
			}
	
			if !empty(safe_visible_exits) {
				target_exit <- safe_visible_exits closest_to self.location;
				target_cell <- (evac_cell where each.walkable) closest_to target_exit.location;
	
				knows_exit <- true;
				wander_cell <- nil;
	
				do add_belief(exitKnown);
			}
		}
	}

	reflex guard_keep_exit_knowledge
	when: role = "guard" and !evacuated and target_cell = nil {
		do learn_nearest_exit;
	}

	rule belief: exitKnown
		new_desire: evacuate
		remove_desire: waitForGuidance
		remove_intention: waitForGuidance;

	rule belief: guardDoneGuiding
		new_desire: evacuate
		remove_desire: guideGuests
		remove_intention: guideGuests;

	rule belief: fireDanger
		new_desire: fleeFire
		remove_desire: waitForGuidance
		remove_intention: waitForGuidance;
	
	rule belief: panicking
		new_desire: fleeFire
		remove_desire: waitForGuidance
		remove_intention: waitForGuidance;
		
	rule belief: gregarism
		new_desire: gregarism
		remove_desire: waitForGuidance
		remove_intention: waitForGuidance;
	
	plan guest_wanders_until_exit_known intention: waitForGuidance
	priority: 1
	when: role = "guest" and !knows_exit and !evacuated
	finished_when: knows_exit or evacuated {
		do wander_randomly(guest_wander_speed);
	}

	plan guest_flees_from_fire intention: fleeFire
	priority: 80
	when: role = "guest" and !evacuated and !knows_exit
	finished_when: evacuated or knows_exit {
		do flee_from_fire;
	}

	plan guest_evacuates intention: evacuate
	priority: 100
	when: role = "guest" and !evacuated and knows_exit and target_cell != nil
	finished_when: evacuated {
		do move_to_target_exit;
	}
	
	plan guard_guides_guests intention: guideGuests
	priority: 20
	when: role = "guard" and !evacuated and !guard_can_evacuate
	finished_when: guard_can_evacuate or evacuated {
		do inform_nearby_guests;
		do check_visible_guests;
		do wander_randomly(guard_patrol_speed);
	}

	plan guard_evacuates intention: evacuate
	priority: 100
	when: role = "guard" and !evacuated and guard_can_evacuate and knows_exit and target_cell != nil
	finished_when: evacuated {
		do move_to_target_exit;
	}
	
	plan guest_follows_crowd intention: gregarism
	priority: 60
	when: role = "guest" and !evacuated and !knows_exit and crowd_leader != nil
	finished_when: evacuated or knows_exit or crowd_leader = nil {
		do follow_crowd;
	}

aspect default {
	if role = "guard" {
		if guard_can_evacuate {
			// Guard has finished guiding and is evacuating
			draw circle(3) color: #purple border: #black;
		} else {
			// Guard is still patrolling/guiding
			draw circle(3) color: #cyan border: #black;
		}
	} else {
		if evacuated {
			draw circle(2) color: #gray border: #black;
		} else if knows_exit and panic >= panic_threshold {
			// Guest knows exit, but is panicked
			draw circle(2.7) color: #orange border: #black;
		} else if knows_exit {
			// Guest knows exit and evacuates normally
			draw circle(2.4) color: #green border: #black;
		} else if panic >= panic_threshold {
			// Guest does not know exit and flees from fire
			draw circle(2.7) color: #red border: #black;
		} else if crowd_leader != nil {
			// Guest follows another evacuating guest
			draw circle(2.5) color: #yellow border: #black;
		} else if has_fire_danger_belief {
			// Guest has perceived fire danger, but is not fully panicked
			draw circle(2.4) color: #pink border: #black;
		} else {
			// Guest has no exit knowledge and is wandering/waiting
			draw circle(2) color: #blue border: #black;
		}
	}
}
}

experiment Evacuation_MVP type: gui {

	float minimum_cycle_duration <- 0.05;

	output {
		display map {
			species festival_boundary aspect: default;
			grid evac_cell border: #darkgray;
			species building aspect: default;
			species evac_exit aspect: default;
			species person aspect: default;
		}

		monitor "Cycle" value: cycle;
		monitor "People remaining" value: length(person);
		monitor "Buildings on fire" value: length(building where each.on_fire);
		monitor "Open exits" value: length(evac_exit where each.is_open);
		monitor "Walkable cells" value: length(evac_cell where each.walkable);
		monitor "Spawn cells" value: length(evac_cell where each.can_spawn);
		monitor "Blocked building cells" value: length(evac_cell where each.blocked_by_building);
		monitor "Inside boundary cells" value: length(evac_cell where each.inside_boundary);
	}
}