// SUMMIT terrain kernels: priority flood, stream-power landscape evolution, droplet erosion.
// Built as a shared library and called from gen_terrain.py via ctypes (build-time only).
#include <math.h>
#include <stdlib.h>
#include <string.h>
#include <stdint.h>

typedef struct { float v; int i; } Node;
typedef struct { Node *a; int n, cap; } Heap;

static void hpush(Heap *h, float v, int i) {
    if (h->n >= h->cap) { h->cap = h->cap ? h->cap * 2 : 1024; h->a = realloc(h->a, sizeof(Node) * h->cap); }
    int k = h->n++;
    while (k > 0) {
        int p = (k - 1) >> 1;
        if (h->a[p].v <= v) break;
        h->a[k] = h->a[p];
        k = p;
    }
    h->a[k].v = v; h->a[k].i = i;
}

static Node hpop(Heap *h) {
    Node top = h->a[0];
    Node last = h->a[--h->n];
    int k = 0;
    for (;;) {
        int c = 2 * k + 1;
        if (c >= h->n) break;
        if (c + 1 < h->n && h->a[c + 1].v < h->a[c].v) c++;
        if (h->a[c].v >= last.v) break;
        h->a[k] = h->a[c];
        k = c;
    }
    if (h->n > 0) h->a[k] = last;
    return top;
}

static const int DX8[8] = {-1, 0, 1, -1, 1, -1, 0, 1};
static const int DY8[8] = {-1, -1, -1, 0, 0, 1, 1, 1};
static const float DD8[8] = {1.41421356f, 1, 1.41421356f, 1, 1, 1.41421356f, 1, 1.41421356f};

// Fill depressions with epsilon gradient. outlet: cells that drain out of the map.
// order (optional, size nx*ny): receives the pop order (a valid topological order).
void priority_flood(float *h, int nx, int ny, float eps, const uint8_t *outlet, int *order) {
    int N = nx * ny;
    uint8_t *closed = calloc(N, 1);
    Heap hp = {0};
    for (int i = 0; i < N; i++) {
        if (outlet[i]) { closed[i] = 1; hpush(&hp, h[i], i); }
    }
    int oc = 0;
    while (hp.n > 0) {
        Node c = hpop(&hp);
        if (order) order[oc++] = c.i;
        int cx = c.i % nx, cy = c.i / nx;
        for (int k = 0; k < 8; k++) {
            int x = cx + DX8[k], y = cy + DY8[k];
            if (x < 0 || y < 0 || x >= nx || y >= ny) continue;
            int j = y * nx + x;
            if (closed[j]) continue;
            closed[j] = 1;
            float lim = c.v + eps * DD8[k];
            if (h[j] < lim) h[j] = lim;
            hpush(&hp, h[j], j);
        }
    }
    free(hp.a);
    free(closed);
}

// One or more implicit stream-power iterations (Braun & Willett 2013) with hillslope diffusion.
// h: heights, U: uplift rate, K: erodibility, kd: diffusivity, dx: cell size.
void thermal_map(float *H, int n, const float *talus, float cell, int iters, float rate);

void spl_run(float *h, const float *U, const float *K, const float *kd, int n, float dx, float dt,
             float m, int iters, const uint8_t *outlet, float *area_out, const float *talus) {
    int N = n * n;
    float *F = malloc(sizeof(float) * N);
    int *order = malloc(sizeof(int) * N);
    int *rec = malloc(sizeof(int) * N);
    float *rd = malloc(sizeof(float) * N);
    float *A = malloc(sizeof(float) * N);
    float *lap = malloc(sizeof(float) * N);
    for (int it = 0; it < iters; it++) {
        memcpy(F, h, sizeof(float) * N);
        priority_flood(F, n, n, 1e-3f, outlet, order);
        for (int i = 0; i < N; i++) {
            rec[i] = i; rd[i] = dx;
            if (outlet[i]) continue;
            int cx = i % n, cy = i / n;
            float best = 0.0f;
            for (int k = 0; k < 8; k++) {
                int x = cx + DX8[k], y = cy + DY8[k];
                if (x < 0 || y < 0 || x >= n || y >= n) continue;
                int j = y * n + x;
                float s = (F[i] - F[j]) / (DD8[k] * dx);
                if (s > best) { best = s; rec[i] = j; rd[i] = DD8[k] * dx; }
            }
        }
        for (int i = 0; i < N; i++) A[i] = dx * dx;
        for (int k = N - 1; k >= 0; k--) {
            int i = order[k];
            if (rec[i] != i) A[rec[i]] += A[i];
        }
        for (int k = 0; k < N; k++) {
            int i = order[k];
            if (outlet[i]) continue;
            int r = rec[i];
            if (r == i) { h[i] += dt * U[i]; continue; }
            float f = K[i] * powf(A[i], m) * dt / rd[i];
            float nh = (h[i] + dt * U[i] + f * h[r]) / (1.0f + f);
            h[i] = nh;
        }
        // diffusion
        for (int y = 0; y < n; y++) {
            for (int x = 0; x < n; x++) {
                int i = y * n + x;
                if (outlet[i]) { lap[i] = 0; continue; }
                float c = h[i];
                float l = h[y * n + (x > 0 ? x - 1 : x)];
                float r = h[y * n + (x < n - 1 ? x + 1 : x)];
                float u = h[(y > 0 ? y - 1 : y) * n + x];
                float d = h[(y < n - 1 ? y + 1 : y) * n + x];
                lap[i] = (l + r + u + d - 4 * c) / (dx * dx);
            }
        }
        for (int i = 0; i < N; i++) h[i] += kd[i] * dt * lap[i];
        if (talus) thermal_map(h, n, talus, dx, 2, 0.5f);
    }
    if (area_out) memcpy(area_out, A, sizeof(float) * N);
    free(F); free(order); free(rec); free(rd); free(A); free(lap);
}

// ---------------------------------------------------------------- droplet erosion
static uint64_t rng_state = 88172645463325252ULL;
static inline double rnd(void) {
    rng_state ^= rng_state << 13; rng_state ^= rng_state >> 7; rng_state ^= rng_state << 17;
    return (rng_state >> 11) * (1.0 / 9007199254740992.0);
}

static inline void hgrad(const float *H, int n, float x, float y, float *h, float *gx, float *gy) {
    int ix = (int)x, iy = (int)y;
    float fx = x - ix, fy = y - iy;
    int i = iy * n + ix;
    float a = H[i], b = H[i + 1], c = H[i + n], d = H[i + n + 1];
    *gx = (b - a) * (1 - fy) + (d - c) * fy;
    *gy = (c - a) * (1 - fx) + (d - b) * fx;
    *h = a * (1 - fx) * (1 - fy) + b * fx * (1 - fy) + c * (1 - fx) * fy + d * fx * fy;
}

// Heights in cell units.  strength (optional) scales erosion per cell.
void erode(float *H, int n, int droplets, unsigned int seed, int radius, int max_steps,
           float inertia, float cap_f, float min_cap, float erode_s, float depo_s, float evap, float grav,
           const float *strength) {
    rng_state = 88172645463325252ULL ^ ((uint64_t)seed * 2654435761ULL);
    // brush
    int bs = (2 * radius + 1) * (2 * radius + 1);
    int *box = malloc(sizeof(int) * bs), *boy = malloc(sizeof(int) * bs);
    float *bw = malloc(sizeof(float) * bs);
    int nb = 0; float bsum = 0;
    for (int y = -radius; y <= radius; y++)
        for (int x = -radius; x <= radius; x++) {
            float d = sqrtf((float)(x * x + y * y));
            if (d <= radius) { box[nb] = x; boy[nb] = y; bw[nb] = radius - d + 0.001f; bsum += bw[nb]; nb++; }
        }
    for (int i = 0; i < nb; i++) bw[i] /= bsum;
    float lo = radius + 1.0f, hi = n - radius - 2.0f;
    for (int dI = 0; dI < droplets; dI++) {
        float x = lo + rnd() * (hi - lo), y = lo + rnd() * (hi - lo);
        float dx = 0, dy = 0, speed = 1, water = 1, sed = 0;
        for (int s = 0; s < max_steps; s++) {
            int ix = (int)x, iy = (int)y;
            float fx = x - ix, fy = y - iy;
            float h, gx, gy;
            hgrad(H, n, x, y, &h, &gx, &gy);
            dx = dx * inertia - gx * (1 - inertia);
            dy = dy * inertia - gy * (1 - inertia);
            float len = sqrtf(dx * dx + dy * dy);
            if (len < 1e-9f) {
                float a = rnd() * 6.2831853f; dx = cosf(a); dy = sinf(a);
            } else { dx /= len; dy /= len; }
            float nx = x + dx, ny = y + dy;
            if (nx < lo || nx > hi || ny < lo || ny > hi) break;
            float nh, t1, t2;
            hgrad(H, n, nx, ny, &nh, &t1, &t2);
            float dh = nh - h;
            float cap = -dh * speed * water * cap_f;
            if (cap < min_cap) cap = min_cap;
            if (sed > cap || dh > 0) {
                float amt = dh > 0 ? fminf(dh, sed) : (sed - cap) * depo_s;
                sed -= amt;
                int i = iy * n + ix;
                H[i] += amt * (1 - fx) * (1 - fy);
                H[i + 1] += amt * fx * (1 - fy);
                H[i + n] += amt * (1 - fx) * fy;
                H[i + n + 1] += amt * fx * fy;
            } else {
                float es = strength ? strength[iy * n + ix] : 1.0f;
                float amt = fminf((cap - sed) * erode_s * es, -dh);
                for (int b = 0; b < nb; b++) {
                    int j = (iy + boy[b]) * n + (ix + box[b]);
                    float w = amt * bw[b];
                    H[j] -= w;
                }
                sed += amt;
            }
            speed = sqrtf(fmaxf(speed * speed - dh * grav, 0.0f));
            water *= (1 - evap);
            x = nx; y = ny;
        }
    }
    free(box); free(boy); free(bw);
}

// Thermal erosion (talus in height units per cell).
void thermal(float *H, int n, float talus, int iters, float rate) {
    float *D = malloc(sizeof(float) * n * n);
    for (int it = 0; it < iters; it++) {
        memset(D, 0, sizeof(float) * n * n);
        for (int y = 1; y < n - 1; y++)
            for (int x = 1; x < n - 1; x++) {
                int i = y * n + x;
                float c = H[i];
                for (int k = 0; k < 8; k++) {
                    int j = (y + DY8[k]) * n + x + DX8[k];
                    float d = c - H[j];
                    float t = talus * DD8[k];
                    if (d > t) {
                        float mv = (d - t) * rate * 0.125f;
                        D[i] -= mv; D[j] += mv;
                    }
                }
            }
        for (int i = 0; i < n * n; i++) H[i] += D[i];
    }
    free(D);
}

// Sun visibility by horizon marching. dirx/diry: horizontal step direction (cells), rise: height per cell.
void sun_shadow(const float *H, int n, float dirx, float diry, float rise, int steps, float soft, float *out) {
    for (int y = 0; y < n; y++)
        for (int x = 0; x < n; x++) {
            float h0 = H[y * n + x];
            float vis = 1.0f;
            float dist = 0.0f;
            float stepl = 1.0f;
            for (int s = 0; s < steps; s++) {
                dist += stepl;
                if (s > 64) stepl = 2.0f;
                if (s > 160) stepl = 4.0f;
                float px = x + dirx * dist, py = y + diry * dist;
                if (px < 0 || py < 0 || px >= n - 1 || py >= n - 1) break;
                int ix = (int)px, iy = (int)py;
                float fx = px - ix, fy = py - iy;
                int i = iy * n + ix;
                float hh = H[i] * (1 - fx) * (1 - fy) + H[i + 1] * fx * (1 - fy) + H[i + n] * (1 - fx) * fy + H[i + n + 1] * fx * fy;
                float ray = h0 + dist * rise;
                float v = 1.0f - (hh - ray + soft * 0.25f) / soft;
                if (v < vis) vis = v;
                if (vis <= 0.0f) { vis = 0.0f; break; }
            }
            out[y * n + x] = vis < 0 ? 0 : (vis > 1 ? 1 : vis);
        }
}

// Thermal erosion with a per-cell talus (tan of the critical angle); heights in metres, cell = spacing.
void thermal_map(float *H, int n, const float *talus, float cell, int iters, float rate) {
    float *D = malloc(sizeof(float) * n * n);
    for (int it = 0; it < iters; it++) {
        memset(D, 0, sizeof(float) * n * n);
        for (int y = 1; y < n - 1; y++)
            for (int x = 1; x < n - 1; x++) {
                int i = y * n + x;
                float c = H[i];
                float tl = talus[i] * cell;
                for (int k = 0; k < 8; k++) {
                    int j = (y + DY8[k]) * n + x + DX8[k];
                    float d = c - H[j];
                    float t = tl * DD8[k];
                    if (d > t) {
                        float mv = (d - t) * rate * 0.125f;
                        D[i] -= mv; D[j] += mv;
                    }
                }
            }
        for (int i = 0; i < n * n; i++) H[i] += D[i];
    }
    free(D);
}
