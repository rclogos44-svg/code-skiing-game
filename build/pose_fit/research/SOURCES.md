# Grab reference photos (not stored in the repo)

Joints were placed by eye on these freely licensed Wikimedia Commons photos; the JSON files here
hold only those 2D points (image pixel coordinates). Draw them with
`python3 overlay.py PHOTO.jpg KEYPOINTS.json OUT.jpg [x0,y0,x1,y1] [scale]`.

| Keypoints | Commons file | Licence / author | Grab |
|---|---|---|---|
| safety_y39.json | 2020-01-20 Freestyle skiing at the 2020 Winter Youth Olympics – Men's Freeski Slopestyle – Finale – 1st run (Martin Rulsch) 040.jpg (960 px thumb) | CC BY-SA 4.0, Martin Rulsch | Safety (same hand at the boot) |
| front_hp10.json | 2020-01-20 Freestyle skiing at the 2020 Winter Youth Olympics – Women's Halfpipe – Final – 2nd run (Martin Rulsch) 11.jpg (960 px thumb) | CC BY-SA 4.0, Martin Rulsch | front grab, skis held upright (Truck Driver shape) |
| tail_673.json | 673rd FSS hosts 2014 Spring Meltdown event 140322-F-XA488-296.jpg (960 px thumb) | Public domain, U.S. Air Force / Staff Sgt. Sheila deVera | Tail |

Also used for checking, without keypoints: "Freeskiing mute grab.jpg" (Richyw, CC BY-SA 3.0),
"Vince Maharavo Stubai.jpg" (CC BY-SA 4.0, tail grab).
