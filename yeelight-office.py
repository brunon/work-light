#!/usr/bin/python3
#
# Documentation: https://www.yeelight.com/download/Yeelight_Inter-Operation_Spec.pdf
#

import socket  
import time
import fcntl
import re
import os
import errno
import struct
import json
import argparse
import traceback
from threading import Thread
from time import sleep
from collections import OrderedDict

current_command_id = 0
debug = False

def next_cmd_id():
  global current_command_id
  current_command_id += 1
  return current_command_id
    
def operate_on_bulb(method: str, params: list):
  bulb_ip="10.0.0.93"
  port=55443
  msg = {
    'id': next_cmd_id(),
    'method': method,
    'params': params
  }
  try:
    tcp_socket = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    if debug: print("connect ",bulb_ip, port ,"...")
    tcp_socket.connect((bulb_ip, port))
    command = json.dumps(msg) + "\r\n"
    if debug: print("sending: ", command)
    tcp_socket.send(command.encode())
    resp = tcp_socket.recv(1024)
    if debug: print("response = ", resp)
    tcp_socket.close()
  except Exception as e:
    print("Unexpected error:", e)
    traceback.print_exc()

def set_power(power, effect, duration):
  mode = 2 # RGB
  operate_on_bulb("set_power", [power, effect, duration, mode])

def set_bright(bright):
  operate_on_bulb("set_bright", [bright])

def set_color(red, green, blue):
  rgb = (red * 65536) + (green * 256) + blue
  operate_on_bulb("set_rgb", [rgb])


parser = argparse.ArgumentParser()
parser.add_argument('--debug', action='store_true')
parser.add_argument('--mode', required=True,
                    choices=['dnd', 'off', 'work', 'warning'])
args = parser.parse_args()

debug = args.debug

if args.mode == 'off':
  set_power('off', 'smooth', 0)

elif args.mode == 'dnd':
  set_power('on', 'smooth', 5)
  set_bright(75)
  set_color(139, 0, 0)

elif args.mode == 'work':
  set_power('on', 'smooth', 5)
  set_bright(20)
  set_color(0, 255, 0)

elif args.mode == 'warning':
  set_power('on', 'smooth', 5)
  set_bright(75)
  set_color(255, 102, 0)
  
