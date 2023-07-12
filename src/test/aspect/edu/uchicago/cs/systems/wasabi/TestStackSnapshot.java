package edu.uchicago.cs.systems.wasabi;

import java.util.ArrayList;
import edu.uchicago.cs.systems.wasabi.StackSnapshot;

import static org.junit.Assert.*;
import org.junit.Test;

class TestStackSnapshot {
  
  @Test
  public void testIsNullOrEmpty() {
    StackSnapshot stackSnapshot = new StackSnapshot();
    assertFalse(stackSnapshot.isNullOrEmpty());

    StackSnapshot emptyStackSnapshot = new StackSnapshot(null);
    assertTrue(emptyStackSnapshot.isNullOrEmpty());
  }

  @Test
  public void testHasFrame() {
    ArrayList<String> testStack = new ArrayList() { 
        {
          add("baz(Baz.java:42)");
          add("bar(Bar.java:42)"); 
          add("foo(Foo.java:42)"); 
        } 
      };

    StackSnapshot stackSnap = new StackSnapshot(testStack);
    for (String frame : testStack) {
      assertTrue(stackSnap.hasFrame(frame));
    }

    assertFalse(stackSnap.hasFrame("not-a-frame"));
  }

  @Test
  public void testGetQualifiedName() {
    String frameFoo = "foo(Foo.java:42)";
    String frameBar = "bar[0](Bar.java:42)";
    
    assertEquals(StackSnapshot.getQualifiedName(frameFoo), "foo");
    assertEquals(StackSnapshot.getQualifiedName(frameBar), "bar[0]");
  }
}
