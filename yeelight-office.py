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
bulb_ip = "10.0.0.93"
port = 55443

def next_cmd_id():
  global current_command_id
  current_command_id += 1
  return current_command_id
    
def operate_on_bulb(method: str, params: list):
  msg = {
    'id': next_cmd_id(),
    'method': method,
    'params': params
  }
  command = json.dumps(msg) + "\r\n"
  if debug: print("sending: ", command)
  tcp_socket.send(command.encode())
  resp = json.loads(tcp_socket.recv(1024))
  if debug: print("response = ", resp)
  if 'error' in resp:
    raise RuntimeError('error with operation ' + method, resp['error'].get('message'))       

def set_power(power, effect, duration):
  mode = 2 # RGB
  operate_on_bulb("set_power", [power, effect, duration, mode])

def set_bright(bright):
  operate_on_bulb("set_bright", [bright])

def set_color(rgb_hex, effect, duration):
  rgb = int(rgb_hex, 16)
  operate_on_bulb("set_rgb", [rgb, effect, duration])


if __name__ == '__main__':
  parser = argparse.ArgumentParser()
  parser.add_argument('--debug', action='store_true')
  parser.add_argument('--mode', required=True, type=str,
                      choices=['dnd', 'off', 'work', 'warning'])
  args = parser.parse_args()

  debug = args.debug
  if debug: print('Connect:', bulb_ip, port, '...')
  tcp_socket = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
  tcp_socket.connect((bulb_ip, port))

  if args.mode == 'off':
    set_power('off', 'smooth', 0)

  elif args.mode == 'dnd':
    set_power('on', 'smooth', 5)
    set_bright(75)
    set_color('FF0000', 'smooth', 5)

  elif args.mode == 'work':
    set_power('on', 'smooth', 5)
    set_bright(50)
    set_color('00FF7F', 'smooth', 5)

  elif args.mode == 'warning':
    set_power('on', 'smooth', 5)
    set_bright(75)
    set_color('FFA500', 'smooth', 5)
  
  tcp_socket.close()
