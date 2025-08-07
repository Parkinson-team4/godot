func _ready():
	var skeleton = $Skeleton3D
	
	if skeleton:
		# 왼쪽 팔 내리기
		var left_arm = skeleton.find_bone("MCH-lip_arm.B.L.001")
		if left_arm != -1:
			skeleton.set_bone_pose_rotation(left_arm, Quaternion.from_euler(Vector3(0, 0, 0)))
		
		# 오른쪽 팔 내리기  
		var right_arm = skeleton.find_bone("MCH-lip_arm.B.R.001")
		if right_arm != -1:
			skeleton.set_bone_pose_rotation(right_arm, Quaternion.from_euler(Vector3(0, 0, 0)))
		
		# 또는 더 자연스럽게 살짝 내리기
		# skeleton.set_bone_pose_rotation(left_arm, Quaternion.from_euler(Vector3(0, 0, -0.3)))
		# skeleton.set_bone_pose_rotation(right_arm, Quaternion.from_euler(Vector3(0, 0, 0.3)))
