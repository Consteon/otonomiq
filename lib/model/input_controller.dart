import 'package:flutter/cupertino.dart';
import '../global.dart';

class InputController {
  int position;
  TextEditingController controller;
  String initialValue;
  String finalData = emptyString; // put string here if final output data
  List<List<dynamic>?>? execute1;
  List<List<dynamic>?>? execute2; // not used
  // execute1 are used to execute a particular function in a widget. it will be
  // triggered by RBT or other action button
  // execute1 = [
  //   [<GlobalKey<FtzAutoNumberState>>,'generate_number',<template>],
  // ]

  Map<String, dynamic>? table; // optional. it will content the table that
  // need to be created at the saveSend button.
  bool isEnabled;
  bool initialIsEnabled;
  dynamic stateObject; // Holds state for complex widgets
  dynamic initialStateObject; // Initial state for reset purposes

  InputController(
    this.position,
    this.controller,
    this.initialValue,
    this.finalData, {
    this.execute1,
    this.execute2,
    this.table, // Added as an optional named parameter
    this.isEnabled = true,
    this.initialIsEnabled = true,
    this.stateObject,
    this.initialStateObject,
  });

  void dispose() {
    controller.dispose();
    // stateObject.dispose();
  }
}
