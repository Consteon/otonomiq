/* by reference wrapper
   This is a class for passing by reference a variable. Usage example:

void alter(ByReferenceWrapper data) {
  data.value++;
}

main() {
  var data = new ByReferenceWrapper(5);
  devPrint(data.value); // 5
  alter(data);
  devPrint(data.value); // 6
}

*/

class ByReferenceWrapper {
  dynamic value;
  ByReferenceWrapper(this.value);
}