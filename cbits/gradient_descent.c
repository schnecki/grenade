#include "gradient_descent.h"
#include <math.h>

void descend_sgd_cpu(int len, RealNum rate, RealNum momentum, RealNum regulariser,
    const RealNum* weights,
    const RealNum* gradient,
    const RealNum* last,
    RealNum* outputWeights, RealNum* outputMomentum) {

  #pragma omp parallel for
  for (int i = 0; i < len; i++) {
      outputMomentum[i] = momentum * last[i] - rate * gradient[i];
      outputWeights[i] = weights[i] + outputMomentum[i] - (rate * regulariser) * weights[i];
  }
}


void descend_adam_cpu(int len, int t, RealNum alpha, RealNum beta1, RealNum beta2, RealNum epsilon, RealNum lambda,
  RealNum* weights,
  const RealNum* gradient,
  RealNum* m,
  RealNum* v) {
  t = t + 1;

  #pragma omp parallel for
  for (int i = 0; i < len; i++) {
    m[i] = beta1 * m[i] + (1 - beta1) * gradient[i];
    v[i] = beta2 * v[i] + (1 - beta2) * gradient[i] * gradient[i];

    // Clear version (as in Algoritm 1 of the paper)
     /* RealNum mHat = outputM[i] / (1 - pow(beta1, t)); */
    /* RealNum vHat = outputV[i] / (1 - pow(beta2, t)); */
    /* outputWeights[i] = weights[i] - alpha * mHat / (sqrt(vHat) + epsilon); */

    // Slightly more performant version (as described in Section 2 of the paper)
    RealNum alphaT = alpha * sqrt(1 - pow(beta2, t)) / ( 1 - pow(beta1, t));
    weights[i] = weights[i] - alphaT * (m[i] / (sqrt(v[i]) + epsilon) + lambda * weights[i]);
  }


}
