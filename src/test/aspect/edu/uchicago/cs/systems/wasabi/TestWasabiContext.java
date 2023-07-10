package edu.uchicago.cs.systems.wasabi;

import java.util.ArrayList;
import edu.uchicago.cs.systems.wasabi.WasabiContext;

import static org.junit.Assert.*;
import org.junit.Test;

public class TestWasabiContext {
  
  @Test
  public void testIsNullOrEmpty() {
    StackSnapshot stackSnapshot = new StackSnapshot();
    assertFalse(stackSnapshot.isNullOrEmpty());

    StackSnapshot emptyStackSnapshot = new StackSnapshot(null);
    assertTrue(emptyStackSnapshot.isNullOrEmpty());
  }


}
