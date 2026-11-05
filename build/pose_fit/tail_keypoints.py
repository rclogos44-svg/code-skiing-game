# Tail-grab reference photos: 2D joints placed by eye (original pixel coords). In all three the
# skier is side-on, travelling to the image-right: knees up in front, shins folded back, skis
# near-vertical with tips down and tails up behind, back hand on the tail, front arm reaching
# forward/up. "g" = grabbing side, "f" = free side.
PHOTOS = {
    "6.png": {"crop": None, "kp": {
        "head": (150, 172), "chest": (152, 205), "thoracic": (145, 226), "lumbar": (139, 246), "waist": (136, 262),
        "pelvis": (140, 280), "hip_g": (132, 283), "hip_f": (148, 286),
        "knee_g": (165, 335), "knee_f": (178, 318), "ankle_g": (103, 378), "ankle_f": (110, 366),
        "heel_g": (83, 370), "toe_g": (91, 410), "heel_f": (96, 358), "toe_f": (103, 396),
        "shoulder_g": (128, 206), "elbow_g": (86, 216), "hand_g": (56, 230),
        "shoulder_f": (170, 200), "elbow_f": (206, 180), "hand_f": (240, 160)},
        "skis": [((54, 236), (110, 505)), ((66, 232), (122, 490))]},
    "8.webp": {"crop": None, "kp": {
        "head": (292, 270), "chest": (298, 300), "thoracic": (303, 330), "lumbar": (304, 362), "waist": (300, 400),
        "pelvis": (296, 440), "hip_g": (286, 444), "hip_f": (306, 448),
        "knee_g": (318, 500), "knee_f": (330, 470), "ankle_g": (246, 560), "ankle_f": (254, 548),
        "heel_g": (226, 548), "toe_g": (236, 598), "heel_f": (236, 538), "toe_f": (246, 585),
        "shoulder_g": (262, 312), "elbow_g": (216, 348), "hand_g": (188, 372),
        "shoulder_f": (330, 292), "elbow_f": (392, 262), "hand_f": (442, 245)},
        "skis": [((190, 372), (255, 690)), ((200, 380), (268, 688))]},
    "7.png": {"crop": None, "kp": {
        "head": (650, 108), "chest": (652, 142), "thoracic": (642, 176), "lumbar": (632, 210), "waist": (626, 244),
        "pelvis": (626, 272), "hip_g": (640, 278), "hip_f": (612, 276),
        "knee_g": (668, 298), "knee_f": (650, 292), "ankle_g": (704, 320), "ankle_f": (712, 340),
        "heel_g": (722, 312), "toe_g": (690, 345), "heel_f": (728, 326), "toe_f": (700, 362),
        "shoulder_g": (704, 152), "elbow_g": (748, 162), "hand_g": (790, 182),
        "shoulder_f": (600, 136), "elbow_f": (558, 116), "hand_f": (516, 100)},
        "skis": [((792, 202), (612, 468)), ((836, 178), (662, 414))]},
}
BONES = [["pelvis", "hip_g"], ["pelvis", "hip_f"], ["hip_g", "knee_g"], ["knee_g", "ankle_g"], ["hip_f", "knee_f"], ["knee_f", "ankle_f"],
    ["pelvis", "waist"], ["waist", "lumbar"], ["lumbar", "thoracic"], ["thoracic", "chest"], ["chest", "head"],
    ["chest", "shoulder_g"], ["chest", "shoulder_f"], ["shoulder_g", "elbow_g"], ["elbow_g", "hand_g"],
    ["shoulder_f", "elbow_f"], ["elbow_f", "hand_f"],
    ["ankle_g", "heel_g"], ["ankle_g", "toe_g"], ["heel_g", "toe_g"], ["ankle_f", "heel_f"], ["ankle_f", "toe_f"], ["heel_f", "toe_f"]]
