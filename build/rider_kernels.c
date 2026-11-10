// Triangle rasterizer for build/gen_rider.py: fills a W x H grid with per-pixel interpolated vertex
// attributes (and the triangle id), with an optional depth test.  Used to bake the rider's texture
// atlases (rasterizing in UV space) and to draw quick preview images (screen space).
// build: gcc -O3 -shared -fPIC -o .cache/librider.so rider_kernels.c -lm
#include <math.h>
#include <stddef.h>

void raster(int ntri, const int *tri, const float *xy, const float *z, int nattr, const float *attr,
            int W, int H, float *zbuf, float *out, int *tid)
{
	for (int t = 0; t < ntri; t++) {
		int i0 = tri[t * 3], i1 = tri[t * 3 + 1], i2 = tri[t * 3 + 2];
		float x0 = xy[i0 * 2], y0 = xy[i0 * 2 + 1];
		float x1 = xy[i1 * 2], y1 = xy[i1 * 2 + 1];
		float x2 = xy[i2 * 2], y2 = xy[i2 * 2 + 1];
		float area = (x1 - x0) * (y2 - y0) - (x2 - x0) * (y1 - y0);
		if (fabsf(area) < 1e-12f)
			continue;
		float minx = fminf(x0, fminf(x1, x2)), maxx = fmaxf(x0, fmaxf(x1, x2));
		float miny = fminf(y0, fminf(y1, y2)), maxy = fmaxf(y0, fmaxf(y1, y2));
		int ax = (int)floorf(minx), bx = (int)ceilf(maxx);
		int ay = (int)floorf(miny), by = (int)ceilf(maxy);
		if (ax < 0) ax = 0;
		if (ay < 0) ay = 0;
		if (bx > W - 1) bx = W - 1;
		if (by > H - 1) by = H - 1;
		for (int py = ay; py <= by; py++) {
			float cy = py + 0.5f;
			for (int px = ax; px <= bx; px++) {
				float cx = px + 0.5f;
				float w0 = ((x1 - cx) * (y2 - cy) - (x2 - cx) * (y1 - cy)) / area;
				float w1 = ((x2 - cx) * (y0 - cy) - (x0 - cx) * (y2 - cy)) / area;
				float w2 = 1.0f - w0 - w1;
				if (w0 < -1e-5f || w1 < -1e-5f || w2 < -1e-5f)
					continue;
				int pi = py * W + px;
				if (z) {
					float zz = w0 * z[i0] + w1 * z[i1] + w2 * z[i2];
					if (zz >= zbuf[pi])
						continue;
					zbuf[pi] = zz;
				}
				for (int a = 0; a < nattr; a++)
					out[(size_t)pi * nattr + a] = w0 * attr[i0 * nattr + a] + w1 * attr[i1 * nattr + a] + w2 * attr[i2 * nattr + a];
				if (tid)
					tid[pi] = t;
			}
		}
	}
}

// Padding around UV charts: grows
// filled atlas texels into empty ones, `iters` rings of 8-neighbours.
void dilate(int W, int H, int nch, float *img, unsigned char *mask, int iters)
{
	static const int dx[8] = {1, -1, 0, 0, 1, 1, -1, -1};
	static const int dy[8] = {0, 0, 1, -1, 1, -1, 1, -1};
	for (int it = 0; it < iters; it++) {
		int changed = 0;
		for (int y = 0; y < H; y++)
			for (int x = 0; x < W; x++) {
				int p = y * W + x;
				if (mask[p])
					continue;
				for (int k = 0; k < 8; k++) {
					int qx = x + dx[k], qy = y + dy[k];
					if (qx < 0 || qy < 0 || qx >= W || qy >= H)
						continue;
					int q = qy * W + qx;
					if (mask[q] == 1) {
						for (int c = 0; c < nch; c++)
							img[(size_t)p * nch + c] = img[(size_t)q * nch + c];
						mask[p] = 2;
						changed = 1;
						break;
					}
				}
			}
		for (int p = 0; p < W * H; p++)
			if (mask[p] == 2)
				mask[p] = 1;
		if (!changed)
			break;
	}
}

// ---------------------------------------------------------------- mesh simplification
// Quadric error metric edge collapse (Garland & Heckbert).  Collapses the cheapest edge until the
// triangle count reaches `target` or the cheapest collapse costs more than `max_err`; rejects
// collapses that would flip a triangle or make the mesh non-manifold.  V (nv*3) and T (nt*3) are
// rewritten in place; returns the new counts through out_nv / out_nt.
#include <stdlib.h>
#include <string.h>

typedef struct { double q[10]; } Quad;
typedef struct { double cost; int a, b, va, vb; float p[3]; } Edge;

static Edge *heap;
static int hn, hcap;

static void hpush(Edge e)
{
	if (hn == hcap) {
		hcap = hcap ? hcap * 2 : 1024;
		heap = realloc(heap, sizeof(Edge) * hcap);
	}
	int i = hn++;
	while (i > 0) {
		int p = (i - 1) / 2;
		if (heap[p].cost <= e.cost)
			break;
		heap[i] = heap[p];
		i = p;
	}
	heap[i] = e;
}

static Edge hpop(void)
{
	Edge top = heap[0], last = heap[--hn];
	int i = 0;
	for (;;) {
		int c = i * 2 + 1;
		if (c >= hn)
			break;
		if (c + 1 < hn && heap[c + 1].cost < heap[c].cost)
			c++;
		if (heap[c].cost >= last.cost)
			break;
		heap[i] = heap[c];
		i = c;
	}
	if (hn > 0)
		heap[i] = last;
	return top;
}

static void qadd(Quad *a, const Quad *b) { for (int i = 0; i < 10; i++) a->q[i] += b->q[i]; }

static double qeval(const Quad *Q, const double *v)
{
	const double *q = Q->q;
	double x = v[0], y = v[1], z = v[2];
	return q[0] * x * x + 2 * q[1] * x * y + 2 * q[2] * x * z + 2 * q[3] * x + q[4] * y * y + 2 * q[5] * y * z + 2 * q[6] * y
		+ q[7] * z * z + 2 * q[8] * z + q[9];
}

// adjacency: per-vertex list of triangles
static int **vt;
static int *vtn, *vtc;

static void vt_add(int v, int t)
{
	if (vtn[v] == vtc[v]) {
		vtc[v] = vtc[v] ? vtc[v] * 2 : 8;
		vt[v] = realloc(vt[v], sizeof(int) * vtc[v]);
	}
	vt[v][vtn[v]++] = t;
}

static void vt_del(int v, int t)
{
	for (int i = 0; i < vtn[v]; i++)
		if (vt[v][i] == t) {
			vt[v][i] = vt[v][--vtn[v]];
			return;
		}
}

static void tri_normal(const float *V, int a, int b, int c, const float *pa, double *n)
{
	const float *A = pa ? pa : V + a * 3;
	const float *Bv = V + b * 3, *C = V + c * 3;
	double e1[3] = {Bv[0] - A[0], Bv[1] - A[1], Bv[2] - A[2]};
	double e2[3] = {C[0] - A[0], C[1] - A[1], C[2] - A[2]};
	n[0] = e1[1] * e2[2] - e1[2] * e2[1];
	n[1] = e1[2] * e2[0] - e1[0] * e2[2];
	n[2] = e1[0] * e2[1] - e1[1] * e2[0];
	double l = sqrt(n[0] * n[0] + n[1] * n[1] + n[2] * n[2]);
	if (l > 0) { n[0] /= l; n[1] /= l; n[2] /= l; }
}

static Quad *Qs;
static int *ver, *tdead;
static float *VV;
static int *TT;

static Edge make_edge(int a, int b)
{
	Edge e;
	e.a = a; e.b = b; e.va = ver[a]; e.vb = ver[b];
	Quad Q = Qs[a];
	qadd(&Q, &Qs[b]);
	const double *q = Q.q;
	double A[9] = {q[0], q[1], q[2], q[1], q[4], q[5], q[2], q[5], q[7]};
	double rhs[3] = {-q[3], -q[6], -q[8]};
	double det = A[0] * (A[4] * A[8] - A[5] * A[7]) - A[1] * (A[3] * A[8] - A[5] * A[6]) + A[2] * (A[3] * A[7] - A[4] * A[6]);
	double best[3], bc = 1e300;
	double pa[3] = {VV[a * 3], VV[a * 3 + 1], VV[a * 3 + 2]}, pb[3] = {VV[b * 3], VV[b * 3 + 1], VV[b * 3 + 2]};
	double mid[3] = {(pa[0] + pb[0]) / 2, (pa[1] + pb[1]) / 2, (pa[2] + pb[2]) / 2};
	if (fabs(det) > 1e-14) {
		double x[3];
		x[0] = (rhs[0] * (A[4] * A[8] - A[5] * A[7]) - A[1] * (rhs[1] * A[8] - A[5] * rhs[2]) + A[2] * (rhs[1] * A[7] - A[4] * rhs[2])) / det;
		x[1] = (A[0] * (rhs[1] * A[8] - A[5] * rhs[2]) - rhs[0] * (A[3] * A[8] - A[5] * A[6]) + A[2] * (A[3] * rhs[2] - rhs[1] * A[6])) / det;
		x[2] = (A[0] * (A[4] * rhs[2] - rhs[1] * A[7]) - A[1] * (A[3] * rhs[2] - rhs[1] * A[6]) + rhs[0] * (A[3] * A[7] - A[4] * A[6])) / det;
		// only trust the optimum near the edge
		double d2 = (x[0] - mid[0]) * (x[0] - mid[0]) + (x[1] - mid[1]) * (x[1] - mid[1]) + (x[2] - mid[2]) * (x[2] - mid[2]);
		double el = (pa[0] - pb[0]) * (pa[0] - pb[0]) + (pa[1] - pb[1]) * (pa[1] - pb[1]) + (pa[2] - pb[2]) * (pa[2] - pb[2]);
		if (d2 < el * 4.0) {
			bc = qeval(&Q, x);
			memcpy(best, x, sizeof best);
		}
	}
	const double *cand[3] = {pa, pb, mid};
	for (int i = 0; i < 3; i++) {
		double c = qeval(&Q, cand[i]);
		if (c < bc) { bc = c; memcpy(best, cand[i], sizeof best); }
	}
	e.cost = bc < 0 ? 0 : bc;
	e.p[0] = best[0]; e.p[1] = best[1]; e.p[2] = best[2];
	return e;
}

static int other_verts(int v, int *buf, int cap)
{
	int n = 0;
	for (int i = 0; i < vtn[v]; i++) {
		int t = vt[v][i];
		for (int k = 0; k < 3; k++) {
			int w = TT[t * 3 + k];
			if (w == v) continue;
			int dup = 0;
			for (int j = 0; j < n; j++) if (buf[j] == w) { dup = 1; break; }
			if (!dup && n < cap) buf[n++] = w;
		}
	}
	return n;
}

int qem_simplify(int nv, float *V, int nt, int *T, int target, double max_err, int *out_nv, int *out_nt)
{
	VV = V; TT = T;
	Qs = calloc(nv, sizeof(Quad));
	ver = calloc(nv, sizeof(int));
	tdead = calloc(nt, sizeof(int));
	vt = calloc(nv, sizeof(int *));
	vtn = calloc(nv, sizeof(int));
	vtc = calloc(nv, sizeof(int));
	hn = 0;
	for (int t = 0; t < nt; t++) {
		double n[3];
		int a = T[t * 3], b = T[t * 3 + 1], c = T[t * 3 + 2];
		tri_normal(V, a, b, c, NULL, n);
		double d = -(n[0] * V[a * 3] + n[1] * V[a * 3 + 1] + n[2] * V[a * 3 + 2]);
		double q[10] = {n[0] * n[0], n[0] * n[1], n[0] * n[2], n[0] * d, n[1] * n[1], n[1] * n[2], n[1] * d, n[2] * n[2], n[2] * d, d * d};
		for (int k = 0; k < 3; k++) {
			for (int i = 0; i < 10; i++) Qs[T[t * 3 + k]].q[i] += q[i];
			vt_add(T[t * 3 + k], t);
		}
	}
	for (int t = 0; t < nt; t++)
		for (int k = 0; k < 3; k++) {
			int a = T[t * 3 + k], b = T[t * 3 + (k + 1) % 3];
			if (a < b) hpush(make_edge(a, b));
		}
	int alive = nt;
	int nbA[256], nbB[256];
	while (alive > target && hn > 0) {
		Edge e = hpop();
		if (e.va != ver[e.a] || e.vb != ver[e.b])
			continue;
		if (e.cost > max_err)
			break;
		int a = e.a, b = e.b;
		// link condition: exactly two shared neighbours
		int na = other_verts(a, nbA, 256), nb = other_verts(b, nbB, 256);
		int shared = 0;
		for (int i = 0; i < na; i++) for (int j = 0; j < nb; j++) if (nbA[i] == nbB[j]) shared++;
		if (shared != 2)
			continue;
		// no flipped or squashed triangles around either end
		int bad = 0;
		for (int pass = 0; pass < 2 && !bad; pass++) {
			int v = pass ? b : a, o = pass ? a : b;
			for (int i = 0; i < vtn[v] && !bad; i++) {
				int t = vt[v][i];
				int has_o = 0, k0 = 0;
				for (int k = 0; k < 3; k++) { if (T[t * 3 + k] == o) has_o = 1; if (T[t * 3 + k] == v) k0 = k; }
				if (has_o) continue;
				int p1 = T[t * 3 + (k0 + 1) % 3], p2 = T[t * 3 + (k0 + 2) % 3];
				double n0[3], n1[3];
				tri_normal(V, v, p1, p2, NULL, n0);
				tri_normal(V, v, p1, p2, e.p, n1);
				if (n0[0] * n1[0] + n0[1] * n1[1] + n0[2] * n1[2] < 0.3) bad = 1;
			}
		}
		if (bad) {
			continue;
		}
		// collapse b into a
		V[a * 3] = e.p[0]; V[a * 3 + 1] = e.p[1]; V[a * 3 + 2] = e.p[2];
		qadd(&Qs[a], &Qs[b]);
		for (int i = vtn[b] - 1; i >= 0; i--) {
			int t = vt[b][i];
			int has_a = 0;
			for (int k = 0; k < 3; k++) if (T[t * 3 + k] == a) has_a = 1;
			if (has_a) {
				tdead[t] = 1;
				alive--;
				for (int k = 0; k < 3; k++) if (T[t * 3 + k] != b) vt_del(T[t * 3 + k], t);
			} else {
				for (int k = 0; k < 3; k++) if (T[t * 3 + k] == b) T[t * 3 + k] = a;
				vt_add(a, t);
			}
		}
		vtn[b] = 0;
		ver[a]++;
		ver[b]++;
		int n2 = other_verts(a, nbA, 256);
		for (int i = 0; i < n2; i++)
			hpush(make_edge(a, nbA[i]));
	}
	// compact
	int *remap = malloc(sizeof(int) * nv);
	float *V0 = malloc(sizeof(float) * nv * 3);
	memcpy(V0, V, sizeof(float) * nv * 3);
	for (int i = 0; i < nv; i++) remap[i] = -1;
	int nt2 = 0, nv2 = 0;
	for (int t = 0; t < nt; t++) {
		if (tdead[t]) continue;
		for (int k = 0; k < 3; k++) {
			int v = T[t * 3 + k];
			if (remap[v] < 0) {
				remap[v] = nv2;
				V[nv2 * 3] = V0[v * 3]; V[nv2 * 3 + 1] = V0[v * 3 + 1]; V[nv2 * 3 + 2] = V0[v * 3 + 2];
				nv2++;
			}
		}
		T[nt2 * 3] = remap[T[t * 3]]; T[nt2 * 3 + 1] = remap[T[t * 3 + 1]]; T[nt2 * 3 + 2] = remap[T[t * 3 + 2]];
		nt2++;
	}
	*out_nv = nv2;
	*out_nt = nt2;
	for (int i = 0; i < nv; i++) free(vt[i]);
	free(vt); free(vtn); free(vtc); free(Qs); free(ver); free(tdead); free(remap); free(V0); free(heap);
	heap = NULL; hcap = 0;
	return 0;
}
