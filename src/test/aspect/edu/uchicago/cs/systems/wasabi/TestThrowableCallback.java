package edu.uchicago.cs.systems.wasabi;

import java.lang.Thread;

import static org.junit.Assert.*;
import org.junit.Test;

class TestThrowableCallback {

    @Test
    public void testShouldNotThrowException() throws Exception {
        try {
            shouldNotThrow();
        } catch (Exception e) {
            // do nothing
        }
    }

    private void shouldNotThrow() {
        try {
            Thread.sleep(5);
        } catch (InterruptedException e) {
            // do nothing
        }
    }

}
