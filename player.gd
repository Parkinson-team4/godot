extends CharacterBody3D

@export var speed = 5.0
@export var jump_velocity = 4.5
@export var mouse_sensitivity = 0.002  # 마우스 감도 조정

@onready var head = $Head
@onready var camera = $Head/Camera3D

var gravity = ProjectSettings.get_setting("physics/3d/default_gravity")

func _ready():
	if not head:
		push_error("Head 노드를 찾을 수 없습니다!")
		return
		
	# 마우스 강제 캡처
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
	print("플레이어 준비 완료!")

func _input(event):
	# ESC로 마우스 토글
	if event is InputEventKey and event.keycode == KEY_ESCAPE and event.pressed:
		if Input.get_mouse_mode() == Input.MOUSE_MODE_CAPTURED:
			Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
			print("마우스 해제됨")
		else:
			Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
			print("마우스 캡처됨")
		return
	
	# 마우스 시점 변환 (캡처된 상태에서만)
	if event is InputEventMouseMotion and Input.get_mouse_mode() == Input.MOUSE_MODE_CAPTURED:
		# 좌우 회전 (플레이어 전체)
		rotate_y(-event.relative.x * mouse_sensitivity)
		
		# 상하 회전 (헤드만)
		if head:
			head.rotate_x(-event.relative.y * mouse_sensitivity)
			head.rotation.x = clamp(head.rotation.x, deg_to_rad(-90), deg_to_rad(90))

func _physics_process(delta):
	# 중력 적용
	if not is_on_floor():
		velocity.y -= gravity * delta
	
	# 점프 (스페이스바)
	if Input.is_key_pressed(KEY_SPACE) and is_on_floor():
		velocity.y = jump_velocity
		print("점프!")
	
	# 키보드 이동 입력
	var input_dir = Vector2()
	
	if Input.is_key_pressed(KEY_W):
		input_dir.y -= 1
	if Input.is_key_pressed(KEY_S):
		input_dir.y += 1
	if Input.is_key_pressed(KEY_A):
		input_dir.x -= 1
	if Input.is_key_pressed(KEY_D):
		input_dir.x += 1
	
	# 이동 방향 계산 (플레이어가 바라보는 방향 기준)
	var direction = (transform.basis * Vector3(input_dir.x, 0, input_dir.y)).normalized()
	
	# 이동 처리
	if direction:
		velocity.x = direction.x * speed
		velocity.z = direction.z * speed
	else:
		velocity.x = move_toward(velocity.x, 0, speed)
		velocity.z = move_toward(velocity.z, 0, speed)
	
	move_and_slide()
