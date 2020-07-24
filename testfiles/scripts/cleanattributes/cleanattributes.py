#!/usr/bin/python3
"""Cleans configured attributes from all elements in a tree of DITA files."""

from optparse import OptionParser

# Import the os module, for the os.walk function
import os
import sys
import re

# Import XML DOM and etree modules
import xml.dom.minidom
import xml.etree.ElementTree as ET

ROOT_DIR = "."  # Directory you want to start from
EXTENSION = "dita"  # Target file extension

# Attributes to strip (all elements)
ATTR_STRIP = ["outputclass"]

# Parse the command line options
parser = OptionParser()
parser.add_option("-d", "--directory", dest="directory",
                  metavar="DIR", default=ROOT_DIR,
                  help="directory to scan for files with attributes")
parser.add_option("-e", "--extension", dest="extension",
                  metavar="EXT", default=EXTENSION,
                  help="extension for files with attributes to be processed")
# TBC - add options for query and clean modes

(options, args) = parser.parse_args()


def validate_dita_file(file_path):
    """Validate that the passed file path is a DITA source file."""
    # Assume DITA file is true until proven otherwise when a test fails
    valid = True

    # Open XML document using minidom parser
    DOMTree = xml.dom.minidom.parse(file_path)
    collection = DOMTree.documentElement

    # Very quick checks - see if the root element looks valid (type, id)
    if collection.tagName in ["concept", "reference", "task"]:
        print("Root element is of type %s" % collection.tagName)
    else:
        print("Valid type for root element not found")
        valid = False

    if collection.hasAttribute("id"):
        print("Root element has id: %s" % collection.getAttribute("id"))
    else:
        print("ID attribute not found in root element")
        valid = False

    # If and only if all tests were successful, will return true
    return valid


def get_dita_doc_type(doc_path):
    """Extract and return the DOCTYPE string from a passed file path."""
    # Regex to match (roughly) on DOCTYPE declaration
    doctype_regex = r'<!DOCTYPE\s+(?P<name>[a-zA-Z][a-zA-Z-]*)\s+PUBLIC\s+"(?P<public_id>.+)">'

    # Get DOCTYPE declaration from dita file using regex
    with open(doc_path, "r", encoding="utf-8") as f:
        file_contents = f.read()
        doctype_match = re.search(doctype_regex, file_contents)
        f.close()
        if doctype_match is not None:
            doctype = doctype_match.group(0)
            return doctype
        else:
            return None


def clean_dita_attributes(doc_path, doc_type):
    """Erase configured attributes from all elements in passed DITA file."""
    # Load the xml tree for the file
    tree = ET.parse(doc_path)
    root_element = tree.getroot()

    # Go through all elements in file and strip required attributes
    for curr_element in root_element.iter():
        # TODO: Could do with passing cmdline attrs
        for attribute in ATTR_STRIP:
            # print("Stripping all %s attributes from element %s"
            #       % (attribute, curr_element.tag))
            curr_element.attrib.pop(attribute, None)

    # Print out full tree into file (over the passed original)
    tree.write(doc_path, "UTF-8", True)

    # Reinsert the DOCTYPE string as the second line
    # after the XML declaration (ensured by the tree.write() above)
    with open(doc_path, "r", encoding="utf-8") as f:
        new_contents = f.readlines()
        f.close()

    # Insert DOCTYPE line back in (tree write does not respect)
    new_contents.insert(1, doc_type + "\n")

    # Open file again and write out the updates (over the 2nd original)
    with open(doc_path, "w", encoding="utf-8") as f:
        f.writelines(new_contents)
    f.close()


def validate_xml_file():
    """Stub for validating a generic XML file."""
    # Nothing to implement here yet
    return True


# Start main script - walk the directory tree
for dir_name, subdir_list, file_list in os.walk(options.directory):
    print("\n" + "Found directory: %s" % dir_name)

    for fname in file_list:
        # Process only if it's a file with the required extension
        splitName = fname.split('.')
        if splitName[-1] == options.extension:
            # Print out the full file path
            full_path = dir_name + "/" + fname
            print("\n" + full_path)

            # ===VALIDATE===
            # Validate the file contents against the available extensions
            if options.extension == "dita":
                file_valid = validate_dita_file(full_path)

            elif options.extension == "xml":
                file_valid = validate_xml_file()

            else:
                print("Cannot clean attributes on files with the %s extension,"
                      + " exiting." % options.extension)
                sys.exit(1)
            # Check whether file passed and exit if not
            # TODO: Ideally if we exit then should not affect *any* files
            if not file_valid:
                print("Not a valid %s file - shouldn't process,"
                      + " exiting." % options.extension)
                sys.exit(1)
            else:
                print("Validated %s file." % options.extension)

            # ===CLEAN===
            # Clean the attributes from the source file
            if options.extension == "dita":
                # Store the DITA doc type for adding back later
                dita_doc_type = get_dita_doc_type(full_path)
                if dita_doc_type is not None:
                    print("DOCTYPE declaration: %s" % dita_doc_type)
                else:
                    print("No DOCTYPE found in DITA file - can't process,"
                          + " exiting.")

                clean_dita_attributes(full_path, dita_doc_type)
