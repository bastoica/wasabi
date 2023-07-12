package edu.uchicago.cs.systems.wasabi;

import java.util.ArrayList;
import java.util.StringJoiner;

class HashingPrimitives {
  public static int getHashValue(String str1, String str2, String str3) {
    StringJoiner joiner = new StringJoiner("@");
    joiner.add(str1);
    joiner.add(str2);
    joiner.add(str3);

    return joiner.toString().hashCode();
  }

  public static int getHashValue(ArrayList<String> arr) {
    StringJoiner joiner = new StringJoiner("@");
    for (String e : arr) {
      joiner.add(e);
    }

    return joiner.toString().hashCode();
  }
}
