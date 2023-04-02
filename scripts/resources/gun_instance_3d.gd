extends ItemInstance3D
class_name GunInstance3D

signal create_projectile

enum gun_states{FIRING, RELOADING}

# Effects.
@export var blood_impact: PackedScene
@export var dust_impact: PackedScene
@export var bullet_projectile: PackedScene

@export var muzzle: Node3D
@export var muzzle_flash: Node3D
@export var muzzle_flash_animation_player: AnimationPlayer
@export var animation_player: AnimationPlayer

# Audio.
@export var fire_sound: AudioStream
@export var reload_sound: AudioStream
@export var clip_load_sound: AudioStream

# These are sound effects that can be instantiated when a sound is played.
#var sound_3d = preload("res://scenes/audio/sound_3d.tscn")
#var sound_direct = preload("res://scenes/audio/sound_direct.tscn")

# This is an example of how to use them.
#var sound = sound_direct.instance()
#add_child(sound)
#sound.play_sound(audio_stream)

# Optional.
@export var equip_speed = 1.0
@export var unequip_speed = 1.0
@export var reload_speed = 1.0

# Pool of projectiles, these are added and deleted when a gun is fired.
var projectiles = []
# So we can get the correct last position for each bullet.
var projectile_index = 0
# So that the projectile isn't clipping with the gun when spawned.
var projectile_offset = 3.5
# Same as with the projectile pool.
var impact_effects = []

# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	pass # Replace with function body.

func request_action(item_action: String) -> void:
	match item_action:
		"fire":
			request_fire()
		"fire_2":
			request_aim()
		"fire_stop":
			request_fire_stop()
		"fire_2_stop":
			request_aim_stop()
		"drop_item":
			call_deferred("queue_free")
		"reload":
			reload()
		

func can_fire() -> bool:
	if current_state == gun_states.RELOADING:
		return false
	if item_data.current_clip_ammo < 1:
		return false
	if not current_state == gun_states.FIRING:
		return false
	
	return true

func _physics_process(delta: float) -> void:
	pass
	#if current_state == gun_states.FIRING:
		#fire_projectile(bullet_projectile)

func reload():
	if item_data.current_clip_ammo < item_data.max_clip_ammo and item_data.current_extra_ammo > 0 and current_state != gun_states.RELOADING:
		current_state = gun_states.RELOADING
		animation_player.play("reload")
	
# TODO: Better to do as a method call, so you can different states of reload completeness.
func _on_animation_player_animation_finished(anim_name: StringName) -> void:
	if anim_name == "reload":
		var ammo_needed = item_data.max_clip_ammo - item_data.current_clip_ammo
			
		if item_data.current_extra_ammo > ammo_needed:
			item_data.current_clip_ammo = item_data.max_clip_ammo
			item_data.current_extra_ammo -= ammo_needed
		else:
			item_data.current_clip_ammo += item_data.current_extra_ammo
			item_data.current_extra_ammo = 0
		
		current_state = item_states.DEFAULT

func request_fire() -> void:
	if can_fire():
		if item_data.is_automatic:
			current_state = gun_states.FIRING
			#animation_player.get_animation("fire").loop = true # So we can set it to false later.
			
		else:
			fire_projectile(bullet_projectile)

func fire_projectile(projectile_type) -> void:
	current_state = gun_states.FIRING
	
	#animation_player.play("fire", -1.0, item_data.rate_of_fire)
	animation_player.stop()
	animation_player.play("fire")
	item_data.current_clip_ammo -= 1
	print(item_data.current_clip_ammo)

func request_fire_stop() -> void:
	current_state == item_states.DEFAULT
	#animation_player.get_animation("fire").loop =

func request_aim() -> void:
	print("aiming")
func request_aim_stop() -> void:
	print("not_aiming")

func process_projectiles(delta):
	for bullet in projectiles:
		# Get the last position of the bullet, from which we can draw the ray.
		bullet.last_position = bullet.translation
		
		# Delete bullet if it's existed for too long.
		bullet.lifetime -= delta
		if bullet.lifetime < 0:
			# Delete the bullet and remove it from the array.
			bullet.queue_free()
			projectiles.erase(bullet)
		
		bullet.global_translate(-bullet.transform.basis.z * item_data.projectile_speed)
		var space_state = get_world_3d().direct_space_state
		
		var ray_parameters := PhysicsRayQueryParameters3D.create(
				bullet.last_position,
				bullet.global_transform.origin,) #TODO: collision mask, self
		
		var collision = space_state.intersect_ray(ray_parameters)
		if collision:
			var impact
			# Spawn the hit effect a little bit away from the surface to reduce clipping.
			var impact_position = (collision.position) + (collision.normal * 0.2)
			var hit = collision.collider
			
			# Check if we hit an enemy, then damage them. Spawn the correct impact effect.
			if hit.is_in_group("Enemy"):
				hit.damage(item_data.damage)
				#var new_impact = Global.instantiate_node(blood_impact, impact_position)
				var new_impact = call_deferred("add_child", blood_impact)
				new_impact.position = impact_position
				
				impact_effects.append(new_impact)
			else:
				#var new_impact = Global.instantiate_node(dust_impact, impact_position)
				
				var new_impact = call_deferred("add_child", dust_impact)
				new_impact.position = impact_position
				
				impact_effects.append(new_impact)
			# Delete the bullet and remove it from the array.
			bullet.queue_free()
			projectiles.erase(bullet)
