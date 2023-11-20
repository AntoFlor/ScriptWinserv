#!/usr/bin/python3

import unidecode
import csv

def remove_accent (feed: str):
    with open(feed, encoding='latin-1', mode='r') as f:
        csv_str = f.read()
        csv_str_removed_accent = unidecode.unidecode(csv_str)
    
    with open(f"formated_{feed}", 'w') as f:
        f.write(csv_str_removed_accent)
    return True

if __name__ == "__main__":
    remove_accent('users.csv')
