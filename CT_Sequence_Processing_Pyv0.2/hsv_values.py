import cv2
img = cv2.imread("C:/Research_Files_Swarup/R11-DropsCT/CT_Sequence_Processing_Pyv0.2/results/frames/front/raw/raw_1246.jpeg")
hsv = cv2.cvtColor(img, cv2.COLOR_BGR2HSV)

def mouse_callback(event, x, y, flags, param):
    if event == cv2.EVENT_LBUTTONDOWN:
        print("HSV:", hsv[y, x])
cv2.imshow("frame", img)
cv2.setMouseCallback("frame", mouse_callback)
cv2.waitKey(0)
cv2.destroyAllWindows()