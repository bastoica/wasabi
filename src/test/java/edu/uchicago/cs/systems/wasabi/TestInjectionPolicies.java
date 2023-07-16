package edu.uchicago.cs.systems.wasabi;

import java.util.ArrayList;
import edu.uchicago.cs.systems.wasabi.StackSnapshot;

import static org.junit.Assert.*;
import org.junit.Test;

public class TestInjectionPolicies {
  
  int fakeCount = 1;
  int fakeBound = 2;
  double fakeProbability = 1.0; 

  @Test
  public void testNoInjectionPolicy() {
    InjectionPolicy policy = new NoInjection();
    assertFalse(policy.shouldInject(this.fakeCount, this.fakeProbability));
  }

  @Test
  public void testInjectForeverPolicy() {
    InjectionPolicy policy = new InjectForever();
    assertTrue(policy.shouldInject(this.fakeCount, this.fakeProbability));
  }

  @Test
  public void testInjectForeverWithProbabilityPolicy() {
    InjectionPolicy policy = new InjectForeverWithProbability();
    assertTrue(policy.shouldInject(this.fakeCount, this.fakeProbability));
    assertFalse(policy.shouldInject(this.fakeCount, 0.0));
  }

  @Test
  public void testInjectUpToMaxCountPolicy() {
    InjectionPolicy policy = new InjectUpToMaxCount(this.fakeBound);
    assertTrue(policy.shouldInject(this.fakeCount, this.fakeProbability));
    assertFalse(policy.shouldInject(this.fakeCount + this.fakeBound, this.fakeProbability));
  }

  @Test
  public void testInjectUpToMaxCountWithProbabilityPolicy() {
    InjectionPolicy policy = new InjectUpToMaxCountWithProbability(this.fakeBound);
    assertTrue(policy.shouldInject(this.fakeCount, this.fakeProbability));
    assertFalse(policy.shouldInject(this.fakeCount + this.fakeBound, this.fakeProbability));
    assertFalse(policy.shouldInject(this.fakeCount, 0.0));
  }
}
