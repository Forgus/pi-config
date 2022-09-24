#!/bin/bash
EXTRA_CONFIG=$1
echo 'Step1: change source mirror...'
sudo cp /etc/apt/sources.list /etc/apt/sources.list.bak
sudo cp /etc/apt/sources.list.d/raspi.list /etc/apt/sources.list.d/raspi.list.bak
sudo cat >/etc/apt/sources.list<<EOF
deb https://mirrors.ustc.edu.cn/debian/ bullseye main contrib non-free
deb https://mirrors.ustc.edu.cn/debian/ bullseye-updates main contrib non-free
deb https://mirrors.ustc.edu.cn/debian-security bullseye-security main contrib non-free
EOF
sudo cat>/etc/apt/sources.list.d/raspi.list<<EOF
deb http://mirrors.ustc.edu.cn/archive.raspberrypi.org/debian/ bullseye main
EOF
echo 'Step2: update sources...'
sudo apt update
sudo apt full-upgrade -y
echo 'Step3: enable root login through ssh...'
echo 'PermitRootLogin yes' | sudo tee -a /etc/ssh/sshd_config
echo 'Step4: install common tools...'
sudo apt install iptables fish git neovim nodejs npm python3-venv python3-pip iperf3 -y
curl -SfL https://get.docker.com | sh -
sudo cat >/etc/docker/daemon.json<<EOF
{
  "registry-mirrors": ["https://xx0uqinw.mirror.aliyuncs.com"]
}
EOF
sudo systemctl restart docker
echo 'Step5: config common settings...'
npm config set registry https://registry.npm.taobao.org
echo 'Step6: change network to legacy...'
sudo iptables -F
sudo update-alternatives --set iptables /usr/sbin/iptables-legacy
sudo update-alternatives --set ip6tables /usr/sbin/ip6tables-legacy
echo 'Step7: enabel cgroup...'
echo 'cgroup_memory=1 cgroup_enable=memory' | sudo tee -a /boot/cmdline.txt
echo 'Step8: config neovim...'
mkdir -p ~/.config && cd ~/.config
git clone https://gitee.com/c-w-b/nvim.git
cd ~
echo 'Step9: extra config...'
if [ $# -eq 0 ]
then 
	echo 'no extra config need.'
elif [ ${EXTRA_CONFIG} = 'hat' ]
then
	echo 'startging config cooling hat...'
	sudo apt install python3-smbus i2c-tools
	sudo pip install Adafruit-SSD1306
	usermod -aG i2c ${USER}
	cat >~/rgb_cooling_hat.py<<EOF
import Adafruit_GPIO.I2C as I2C

import time
import os
import smbus
bus = smbus.SMBus(1)

import Adafruit_SSD1306

from PIL import Image
from PIL import ImageDraw
from PIL import ImageFont

import subprocess

hat_addr = 0x0d
rgb_effect_reg = 0x04
fan_reg = 0x08
fan_state = 2
count = 0

# Raspberry Pi pin configuration:
RST = None     # on the PiOLED this pin isnt used

# 128x32 display with hardware I2C:
disp = Adafruit_SSD1306.SSD1306_128_32(rst=RST)

# Initialize library.
disp.begin()

# Clear display.
disp.clear()
disp.display()

# Create blank image for drawing.
# Make sure to create image with mode '1' for 1-bit color.
width = disp.width
height = disp.height
image = Image.new('1', (width, height))

# Get drawing object to draw on image.
draw = ImageDraw.Draw(image)

# Draw a black filled box to clear the image.
draw.rectangle((0,0,width,height), outline=0, fill=0)

# Draw some shapes.
# First define some constants to allow easy resizing of shapes.
padding = -2
top = padding
bottom = height-padding
# Move left to right keeping track of the current x position for drawing shapes.
x = 0

# Load default font.
font = ImageFont.load_default()

# Alternatively load a TTF font.  Make sure the .ttf font file is in the same directory as the python script!
# Some other nice fonts to try: http://www.dafont.com/bitmap.php
# font = ImageFont.truetype('Minecraftia.ttf', 8)

def setFanSpeed(speed):
    bus.write_byte_data(hat_addr, fan_reg, speed&0xff)

def setRGBEffect(effect):
    bus.write_byte_data(hat_addr, rgb_effect_reg, effect&0xff)

def getCPULoadRate():
    f1 = os.popen("cat /proc/stat", 'r')
    stat1 = f1.readline()
    count = 10
    data_1 = []
    for i  in range (count):
        data_1.append(int(stat1.split(' ')[i+2]))
    total_1 = data_1[0]+data_1[1]+data_1[2]+data_1[3]+data_1[4]+data_1[5]+data_1[6]+data_1[7]+data_1[8]+data_1[9]
    idle_1 = data_1[3]

    time.sleep(1)

    f2 = os.popen("cat /proc/stat", 'r')
    stat2 = f2.readline()
    data_2 = []
    for i  in range (count):
        data_2.append(int(stat2.split(' ')[i+2]))
    total_2 = data_2[0]+data_2[1]+data_2[2]+data_2[3]+data_2[4]+data_2[5]+data_2[6]+data_2[7]+data_2[8]+data_2[9]
    idle_2 = data_2[3]

    total = int(total_2-total_1)
    idle = int(idle_2-idle_1)
    usage = int(total-idle)
    print("idle:"+str(idle)+"  total:"+str(total))
    usageRate =int(float(usage * 100/ total))
    print("usageRate:%d"%usageRate)
    return "CPU:"+str(usageRate)+"%"

def getLocalIP():
    ip = os.popen(
        "/sbin/ifconfig wlan0 | grep 'inet' | awk '{print $2}'").read()
    ip = ip[0: ip.find('\n')]
    if(ip == ''):
        ip = os.popen(
            "/sbin/ifconfig wlan0 | grep 'inet' | awk '{print $2}'").read()
        ip = ip[0: ip.find('\n')]
        if(ip == ''):
            ip = 'x.x.x.x'
    if len(ip) > 15:
        ip = 'x.x.x.x'
    return ip

def setOLEDshow():
    # Draw a black filled box to clear the image.
    draw.rectangle((0,0,width,height), outline=0, fill=0)

    #cmd = "top -bn1 | grep load | awk '{printf \"CPU:%.0f%%\", $(NF-2)*100}'"
    #CPU = subprocess.check_output(cmd, shell = True)
    CPU = getCPULoadRate()

    cmd = os.popen('vcgencmd measure_temp').readline()
    CPU_TEMP = cmd.replace("temp=","Temp:").replace("'C\n","C")
    global g_temp
    g_temp = float(cmd.replace("temp=","").replace("'C\n",""))

    cmd = "free -m | awk 'NR==2{printf \"RAM:%s/%s MB \", $2-$3,$2}'"
    MemUsage = subprocess.check_output(cmd, shell = True)
    MemUsage = str(MemUsage).lstrip('b\'')
    MemUsage = MemUsage.rstrip('\'')

    cmd = "df -h | awk '$NF==\"/\"{printf \"Disk:%d/%dMB\", ($2-$3)*1024,$2*1024}'"
    Disk = subprocess.check_output(cmd, shell = True)
    Disk = str(Disk).lstrip('b\'')
    Disk = Disk.rstrip('\'')

    # Write two lines of text.

    draw.text((x, top), str(CPU), font=font, fill=255)
    draw.text((x+56, top), str(CPU_TEMP), font=font, fill=255)
    draw.text((x, top+8), str(MemUsage),  font=font, fill=255)
    draw.text((x, top+16), str(Disk),  font=font, fill=255)
    draw.text((x, top+24), "wlan0:" + str(getLocalIP()),  font=font, fill=255)

    # Display image.
    disp.image(image)
    disp.display()
    time.sleep(.1)

setFanSpeed(0x00)
setRGBEffect(0x03)

while True:
    setOLEDshow()	
    if g_temp >= 48:
        if fan_state != 1:
            setFanSpeed(0x01)
            fan_state = 1        
    elif g_temp <= 40:
        if fan_state != 0:
            setFanSpeed(0x00)
            fan_state = 0
    
    if count == 10:
        setRGBEffect(0x04)
    elif count == 20:
        setRGBEffect(0x02)
    elif count == 30:
        setRGBEffect(0x01)
    elif count == 40:
        setRGBEffect(0x03)
        count = 0
    count += 1
    time.sleep(.5)

EOF
	nohup python ~/rgb_cooling_hat.py &
else
	echo 'not support yet.'
fi
echo 'Step10: use fish...'
chsh -s /usr/bin/fish
fish

