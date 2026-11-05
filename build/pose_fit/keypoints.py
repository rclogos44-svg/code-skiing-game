# 2D joints of the skier in the mute reference photo (5.png, 578x1024 px), placed by eye.
# His chest faces the camera (the zip runs down the middle); the camera is low and close.
# So his RIGHT side is on the image-left: right hand grabs the left ski (a mirrored mute).
KP = {
    "head": (265, 115), "chest": (305, 182), "thoracic": (333, 240), "lumbar": (368, 288),
    "waist": (400, 322), "pelvis": (440, 345), "hip_r": (428, 350), "hip_l": (462, 356),
    "knee_r": (295, 395), "ankle_r": (306, 496), "knee_l": (425, 438), "ankle_l": (402, 506),
    "shoulder_r": (287, 207), "elbow_r": (240, 362), "hand_r": (217, 497),
    "ski_l": (428, 546), "ski_r": (306, 528),        # boot centres on the skis (black boot / red boot)
    "shoulder_l": (360, 162), "elbow_l": (386, 52), "hand_l": (356, -45),
}
BONES = [["pelvis", "hip_r"], ["pelvis", "hip_l"], ["hip_r", "knee_r"], ["knee_r", "ankle_r"], ["hip_l", "knee_l"],
    ["knee_l", "ankle_l"], ["pelvis", "waist"], ["waist", "lumbar"], ["lumbar", "thoracic"], ["thoracic", "chest"], ["chest", "head"],
    ["chest", "shoulder_r"], ["chest", "shoulder_l"], ["shoulder_r", "elbow_r"], ["elbow_r", "hand_r"], ["shoulder_l", "elbow_l"],
    ["elbow_l", "hand_l"]]

# ski axes seen in the photo (two points on each line). The left ski (black boot) is the one his
# right hand holds; the right ski (red boot) crosses it right under the boots.
SKI_LINES = {"l": [(0, 415), (575, 607)], "r": [(575, 272), (100, 675)]}
