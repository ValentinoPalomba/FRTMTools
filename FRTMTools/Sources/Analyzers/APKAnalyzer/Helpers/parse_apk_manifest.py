#!/usr/bin/env python3
"""
Simple APK manifest parser that extracts basic metadata without external dependencies.
Parses binary XML format used in Android APK files.
"""

import sys
import zipfile
import struct

def get_string(data, offset):
    """Extract a null-terminated string from binary data."""
    end = data.find(b'\x00', offset)
    if end == -1:
        return data[offset:].decode('utf-8', errors='ignore')
    return data[offset:end].decode('utf-8', errors='ignore')

def parse_binary_xml(data):
    """
    Parse Android binary XML format to extract string pool and manifest data.
    Android binary XML has a string pool that contains all strings used in the manifest.
    """
    try:
        if len(data) < 8:
            return {'error': 'File too small'}

        # Read XML header
        magic = struct.unpack('<I', data[0:4])[0]
        file_size = struct.unpack('<I', data[4:8])[0]

        # Look for string pool chunk (type 0x001C0001)
        offset = 8
        strings = []

        while offset < len(data) - 8:
            chunk_type = struct.unpack('<I', data[offset:offset+4])[0]
            chunk_size = struct.unpack('<I', data[offset+4:offset+8])[0]

            if chunk_type == 0x001C0001:  # String pool
                string_count = struct.unpack('<I', data[offset+8:offset+12])[0]
                string_offset_base = offset + 28  # Skip header

                # Read string offsets
                offsets = []
                for i in range(string_count):
                    str_offset = struct.unpack('<I', data[offset+28+i*4:offset+32+i*4])[0]
                    offsets.append(str_offset)

                # Read strings
                data_start = offset + 28 + (string_count * 4)
                for str_offset in offsets:
                    str_pos = data_start + str_offset
                    if str_pos < len(data) - 2:
                        # UTF-16 encoded string
                        str_len = struct.unpack('<H', data[str_pos:str_pos+2])[0]
                        if str_len > 0 and str_len < 1000:
                            try:
                                string = data[str_pos+2:str_pos+2+str_len*2].decode('utf-16-le', errors='ignore')
                                strings.append(string)
                            except:
                                pass
                break

            offset += chunk_size if chunk_size > 0 else 1

        # Find package name, versionName, versionCode, app label, and permissions in strings
        package_name = None
        version_name = None
        version_code = None
        app_label = None
        permissions = []

        # Look for uses-permission tag and android.permission.* strings
        uses_permission_idx = -1
        android_name_idx = -1

        for i, s in enumerate(strings):
            if s == 'uses-permission':
                uses_permission_idx = i
            if s == 'name' and uses_permission_idx >= 0:
                android_name_idx = i

        # Extract permissions - look for actual permission strings
        # Real permissions typically have ".permission." in them or start with android.permission.
        for s in strings:
            is_permission = False

            # Standard Android permissions
            if s.startswith('android.permission.'):
                is_permission = True
            # Custom permissions with .permission. in the middle
            elif '.permission.' in s and not s.endswith('Activity') and not s.endswith('Service') and not s.endswith('Receiver') and not s.endswith('Provider'):
                is_permission = True

            if is_permission and s not in permissions:
                permissions.append(s)

        # Look for app label - find the label attribute value
        # Look for patterns like: application -> android:label -> @string/app_name -> actual string
        # Or just find a reasonable user-facing string

        # First, try to find strings that look like app names
        # Characteristics: capitalized, short, no technical indicators
        excluded_labels = ['name', 'label', 'application', 'activity', 'service', 'receiver', 'provider',
                           'RELEASE', 'DEBUG', 'MAIN', 'VERSION', 'SDK', 'MIN', 'MAX', 'TARGET',
                           'true', 'false', 'null', 'value', 'config', 'default', 'string', 'layout',
                           'drawable', 'color', 'dimen', 'style', 'array', 'integer', 'bool', 'id',
                           'attr', 'anim', 'menu', 'raw', 'xml', 'font', 'navigation', 'transition']

        # Look for label-like strings near "application" tag
        app_index = -1
        for i, s in enumerate(strings):
            if s == 'application':
                app_index = i
                break

        # If we found application tag, look at nearby strings
        if app_index >= 0:
            # Check strings within 20 positions of the application tag
            for offset in range(1, min(21, len(strings) - app_index)):
                s = strings[app_index + offset]
                if (2 <= len(s) <= 50 and
                    '/' not in s and
                    not s.startswith('android') and
                    not s.startswith('com.') and
                    not s.startswith('@') and
                    not s.endswith('.xml') and
                    not any(char.isdigit() for char in s) and  # Exclude strings with numbers
                    s.upper() not in [e.upper() for e in excluded_labels]):
                    if s[0].isupper():
                        app_label = s
                        break

        # If still not found, search all strings
        if not app_label:
            for s in strings:
                if (3 <= len(s) <= 50 and
                    '/' not in s and '.' not in s and
                    not s.startswith('android') and
                    not s.startswith('com.') and
                    not s.startswith('@') and
                    not s.endswith('.xml') and
                    s.upper() not in [e.upper() for e in excluded_labels]):
                    # Strong preference for strings that start with capital and contain spaces
                    if s[0].isupper() and ' ' in s:
                        app_label = s
                        break

        # Last resort: any capitalized word without special chars
        if not app_label:
            for s in strings:
                if (3 <= len(s) <= 30 and
                    s[0].isupper() and
                    s.isalpha() and
                    s.upper() not in [e.upper() for e in excluded_labels]):
                    app_label = s
                    break

        for s in strings:
            # Look for package name (Java package format: com.company.app)
            # Must have at least 2 dots, contain letters, and not start with a digit
            if not package_name and '.' in s and len(s) > 5 and len(s) < 200:
                if (s.count('.') >= 2 and
                    any(c.isalpha() for c in s) and
                    all(c.isalnum() or c == '.' or c == '_' for c in s) and
                    not s[0].isdigit() and
                    not s.startswith('android.permission.')):  # Exclude permissions from package detection
                    package_name = s

            # Look for version name (starts with digit and has dots)
            if not version_name and len(s) < 50 and '.' in s:
                if s[0].isdigit() and s.replace('.', '').replace('-', '').replace('_', '')[0:5].replace('b','').replace('a','').replace('rc','').isdigit():
                    version_name = s

        # Try to find version code (large numeric value, typically 6-10 digits)
        for s in strings:
            if s.isdigit() and 5 <= len(s) <= 10:
                if not version_code or int(s) > int(version_code):
                    version_code = s

        # If no app label found, generate one from package name
        if not app_label and package_name:
            # Take the last part of the package name and capitalize it
            # com.google.android.youtube -> Youtube
            parts = package_name.split('.')
            if len(parts) > 0:
                last_part = parts[-1]
                # Capitalize first letter
                app_label = last_part.capitalize()

        return {
            'package': package_name,
            'versionName': version_name,
            'versionCode': version_code,
            'appLabel': app_label,
            'permissions': permissions
        }
    except Exception as e:
        return {'error': str(e)}

def main():
    if len(sys.argv) < 2:
        print("error: No APK file specified")
        sys.exit(1)

    apk_path = sys.argv[1]

    try:
        with zipfile.ZipFile(apk_path, 'r') as apk:
            # Read AndroidManifest.xml
            manifest_data = apk.read('AndroidManifest.xml')
            result = parse_binary_xml(manifest_data)

            # Output in a parseable format
            if result.get('package'):
                print(f"package:{result['package']}")
            if result.get('versionName'):
                print(f"versionName:{result['versionName']}")
            if result.get('versionCode'):
                print(f"versionCode:{result['versionCode']}")
            if result.get('appLabel'):
                print(f"appLabel:{result['appLabel']}")
            if result.get('permissions'):
                for permission in result['permissions']:
                    print(f"permission:{permission}")

            if not result.get('package'):
                print("error: Could not parse package name")

    except Exception as e:
        print(f"error:{str(e)}")
        sys.exit(1)

if __name__ == "__main__":
    main()
