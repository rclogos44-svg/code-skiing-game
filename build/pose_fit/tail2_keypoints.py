# Sideways tail grab photo (9.png, 460x690): seen from below/in front, body tilted ~45 deg off-axis
# (head to his left), right hand on the right tail behind the right shoulder, free arm overhead.
KP = {"head": (313, 180), "chest": (296, 172), "thoracic": (285, 188), "lumbar": (276, 204), "waist": (268, 218),
      "pelvis": (262, 232), "hip_r": (250, 228), "hip_l": (274, 238),
      "knee_r": (225, 280), "knee_l": (252, 262), "ankle_r": (205, 205), "ankle_l": (222, 195),
      "heel_r": (216, 190), "toe_r": (190, 222), "heel_l": (232, 180), "toe_l": (207, 210),
      "shoulder_r": (267, 163), "elbow_r": (262, 154), "hand_r": (255, 147),
      "shoulder_l": (328, 171), "elbow_l": (345, 159), "hand_l": (360, 147)}
SKIS = [((280, 112), (98, 300))]
BONES = [["pelvis", "hip_l"], ["pelvis", "hip_r"], ["hip_l", "knee_l"], ["knee_l", "ankle_l"], ["hip_r", "knee_r"], ["knee_r", "ankle_r"],
    ["pelvis", "waist"], ["waist", "lumbar"], ["lumbar", "thoracic"], ["thoracic", "chest"], ["chest", "head"],
    ["chest", "shoulder_l"], ["chest", "shoulder_r"], ["shoulder_l", "elbow_l"], ["elbow_l", "hand_l"], ["shoulder_r", "elbow_r"],
    ["elbow_r", "hand_r"], ["ankle_l", "heel_l"], ["ankle_l", "toe_l"], ["heel_l", "toe_l"], ["ankle_r", "heel_r"], ["ankle_r", "toe_r"],
    ["heel_r", "toe_r"]]
