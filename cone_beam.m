close all; clear all;

if isfile('data/3D_sino.mat')
    load('data/3D_sino.mat')
else
    %Code for generating true sinogram
    load('data/phantom_crop154.mat');  % unit of the loaded phantom: HU
    phantom = phantom(:,:,1:96); % extract 96 slices for testing

    fprintf('generating noiseless sino...\n');
    down = 1; % downsample rate
    ig_hi = image_geom('nx',840,'dx',500/1024,'nz',96,'dz',0.625,'down',down);
    down = 8; % downsample rate
    cg = ct_geom('ge2', 'down', down);
    A_hi = Gcone(cg, ig_hi, 'type', 'sf2', 'nthread', jf('ncore')*2-1);  
    sino = A_hi * phantom;  clear A_hi;

    save('data/3D_sino.mat', 'sino')
end


down = 1;
ig = image_geom('nx',420,'dx',500/512,'nz',96,'dz',0.625,'down',down);
ig.mask = ig.circ > 0; % can be omitted
mask = ig.mask;

down = 8; % downsample rate
cg = ct_geom('ge2', 'down', down);

A = Gcone(cg, ig, 'type', 'sf2', 'nthread', jf('ncore')*2-1);


%Code for generating preconditioning matrix
if isfile('data/H_E_cone.mat')
    load('data/H_E_cone.mat', 'H')
else
    H = zeros(420,420,96);
    count = 0;
    tic
    for ii=1:42:420
        for jj=1:42:420
            for kk=1:8:96
                disp([num2str(ii),num2str(jj),num2str(kk)])
                ek = zeros(420,420,96);
                ek(ii,jj,kk) = 1;
                H = H + fftn(embed(A' * (A * ek(mask(:))), mask))./fftn(ek);
                count = count + 1;
            end
        end
    end
    toc

    H = real(H)/count;
    save('data/H_E_cone.mat', 'H')
end


N = 420;
M=96;
iters = 1000;
lambda = 1;
sino = reshape(sino, [], 1);


%NCS experiment
alpha = 0.001;
beta = 0.1;
gamma = 0.03;


x = zeros(N,N, M);
u = zeros(size(A, 1), 1);
vx = zeros(N,N,M);
vy = zeros(N,N,M);
vz = zeros(N,N,M);


[kk,ll,mm] = meshgrid(0:(N-1),0:(N-1),0:(M-1));
H =  gamma*ones(N,N,M) + 3*alpha*H + 4*beta^2/alpha*((sin(kk*pi/N)).^2+(sin(ll*pi/N)).^2+(sin(mm*pi/M)).^2);
H = 1./H;

err_vec_NCS = zeros(iters,1);
tic
for ii=1:iters
    %disp(ii)
    xprime = x;
    
    Dpv = vx+vy+vz;
    Dpv(1:N,2:N,1:M) = Dpv(1:N,2:N,1:M) - vx(1:N,1:(N-1),1:M);
    Dpv(2:N,1:N,1:M) = Dpv(2:N,1:N,1:M) - vy(1:(N-1),1:N,1:M);
    Dpv(1:N,1:N,2:M) = Dpv(1:N,1:N,2:M) - vz(1:N,1:N,1:(M-1));
    
    y = embed(A' * u, mask) + beta/alpha * Dpv;
    x = x-real(ifftn(H.*fftn(y)));
    
    
    xprime = (2*x-xprime);
    r = A * xprime(mask(:));
    
    u = double(1/(1+alpha)*(u+alpha*(r-sino)));
    vx(1:N,1:(N-1),1:M) = max(min(vx(1:N,1:(N-1),1:M) + beta*(xprime(1:N,1:(N-1),1:M)-xprime(1:N,2:N,1:M)),lambda*alpha/beta),-lambda*alpha/beta);
    vy(1:(N-1),1:N,1:M) = max(min(vy(1:(N-1),1:N,1:M) + beta*(xprime(1:(N-1),1:N,1:M)-xprime(2:N,1:N,1:M)),lambda*alpha/beta),-lambda*alpha/beta);
    vz(1:N,1:N,1:(M-1)) = max(min(vz(1:N,1:N,1:(M-1)) + beta*(xprime(1:N,1:N,1:(M-1))-xprime(1:N,1:N,2:M)),lambda*alpha/beta),-lambda*alpha/beta);

    err_vec_NCS(ii) = (1/2)*gather(sum(sum(sum((A*x(mask(:))-sino).^2)))) + lambda*gather(sum(sum(sum(abs(x(1:N,1:(N-1),1:M)-x(1:N,2:N,1:M)))))+sum(sum(sum(abs(x(1:(N-1),1:N,1:M)-x(2:N,1:N,1:M)))))+sum(sum(sum(abs(x(1:N,1:N,1:(M-1))-x(1:N,1:N,2:M))))));
    %disp(err_vec_NCS(ii))
end
toc
x_ncs = x;
clear x u vx vy vz


%PDHG experiment
alpha = 0.001;
beta = 0.1;
gamma = 1;

x = zeros(N,N, M);
u = zeros(size(A, 1), 1);
vx = zeros(N,N,M);
vy = zeros(N,N,M);
vz = zeros(N,N,M);

err_vec_PDHG = zeros(iters,1);
tic
for ii=1:iters
    %disp(ii)
    xprime = x;
    
    Dpv = vx+vy+vz;
    Dpv(1:N,2:N,1:M) = Dpv(1:N,2:N,1:M) - vx(1:N,1:(N-1),1:M);
    Dpv(2:N,1:N,1:M) = Dpv(2:N,1:N,1:M) - vy(1:(N-1),1:N,1:M);
    Dpv(1:N,1:N,2:M) = Dpv(1:N,1:N,2:M) - vz(1:N,1:N,1:(M-1));
    
    y = embed(A' * u, mask) + beta/alpha * Dpv;
    x = x-1/gamma*y;
    
    xprime = (2*x-xprime);
    r = A * xprime(mask(:));
    
    u = double(1/(1+alpha)*(u+alpha*(r-sino)));
    vx(1:N,1:(N-1),1:M) = max(min(vx(1:N,1:(N-1),1:M) + beta*(xprime(1:N,1:(N-1),1:M)-xprime(1:N,2:N,1:M)),lambda*alpha/beta),-lambda*alpha/beta);
    vy(1:(N-1),1:N,1:M) = max(min(vy(1:(N-1),1:N,1:M) + beta*(xprime(1:(N-1),1:N,1:M)-xprime(2:N,1:N,1:M)),lambda*alpha/beta),-lambda*alpha/beta);
    vz(1:N,1:N,1:(M-1)) = max(min(vz(1:N,1:N,1:(M-1)) + beta*(xprime(1:N,1:N,1:(M-1))-xprime(1:N,1:N,2:M)),lambda*alpha/beta),-lambda*alpha/beta);

    err_vec_PDHG(ii) = (1/2)*gather(sum(sum(sum((A*x(mask(:))-sino).^2)))) + lambda*gather(sum(sum(sum(abs(x(1:N,1:(N-1),1:M)-x(1:N,2:N,1:M)))))+sum(sum(sum(abs(x(1:(N-1),1:N,1:M)-x(2:N,1:N,1:M)))))+sum(sum(sum(abs(x(1:N,1:N,1:(M-1))-x(1:N,1:N,2:M))))));
    %disp(err_vec_PDHG(ii))
end
toc
x_pdhg = x;
clear x u vx vy vz



%ADMM experiment
alpha = 1;
beta = 0.1;


rng(999);
x = randn(N, N, M);
u = zeros(size(A, 1), 1);
vx = zeros(N, N, M);
vy = zeros(N, N, M);
vz = zeros(N, N, M);

etau = zeros(size(u));
etavx = zeros(size(vx));
etavy = zeros(size(vy));
etavz = zeros(size(vz));

Dxx = zeros(N, N, M);
Dxy = zeros(N, N, M);
Dxz = zeros(N, N, M);

iter_vec = [];
err_vec_ADMM = [];
inner_iters = 0;

H = ones(N, N, M);

tic
for ii=1:(iters/10)
    %disp(ii)
    xprime = x;

    Dpv = compute_Dpv(vx - etavx, vy - etavy, vz - etavz, N, M);

    Gx_tgt = embed(A' * double(u - etau), mask) + beta * Dpv;

    % solve for x.
    [x, kk] = cgsolve(x, Gx_tgt, N, M, A, mask, beta, H);

    inner_iters = inner_iters + kk; 

    Ax = A * x(mask(:));

    % step 4
    u = 1.0/(1.0 + alpha) * (sino + alpha * (Ax + etau));

    % step 5
    [Dxx, Dxy, Dxz] = compute_Dx(x, N, M);

    rhox = Dxx + etavx; 
    rhoy = Dxy + etavy;
    rhoz = Dxz + etavz;

    vx = sign(rhox) .* max(abs(rhox) - lambda/(alpha*beta), 0);
    vy = sign(rhoy) .* max(abs(rhoy) - lambda/(alpha*beta), 0);
    vz = sign(rhoz) .* max(abs(rhoz) - lambda/(alpha*beta), 0);

    % steps 6-8
    etau  = etau -  (u  - Ax);
    etavx = etavx - (vx - Dxx); 
    etavy = etavy - (vy - Dxy);
    etavz = etavz - (vz - Dxz);

    
    iter_vec = [iter_vec inner_iters];
    err_vec_ADMM = [err_vec_ADMM, (1/2)*gather(sum(sum(sum((A*x(mask(:))-sino).^2)))) + lambda*gather(sum(sum(sum(abs(x(1:N,1:(N-1),1:M)-x(1:N,2:N,1:M)))))+sum(sum(sum(abs(x(1:(N-1),1:N,1:M)-x(2:N,1:N,1:M)))))+sum(sum(sum(abs(x(1:N,1:N,1:(M-1))-x(1:N,1:N,2:M))))))];
    %disp(err_vec_ADMM(ii))
end
toc
x_admm = x;


save('cone_beam_results.mat','err_vec_PDHG','err_vec_NCS','err_vec_ADMM','iter_vec')
save('cone_beam_images.mat','x_pdhg','x_ncs','x_admm');
%%
close all; clear all;
load('cone_beam_results.mat')
minval = min([min(err_vec_NCS),min(err_vec_PDHG),min(err_vec_ADMM)])-(1e8);
loglog(1:length(err_vec_NCS),err_vec_NCS-minval,'k','LineWidth',2)

hold on;
loglog(1:length(err_vec_PDHG),err_vec_PDHG-minval,'r--','LineWidth',2)
loglog(iter_vec,err_vec_ADMM-minval,'b:','LineWidth',2)


legend('NCS','PDHG','ADMM')
%xlabel('Iterations')
%ylabel('Objective value suboptimality')

pbaspect([2 1 1])
ylim([1e7,1e15])

ax = gca;
ax.OuterPosition(3)=ax.OuterPosition(4);
outerpos = ax.OuterPosition;
ti = ax.TightInset; 
left = outerpos(1) + ti(1);
bottom = outerpos(2) + ti(2);
ax_width = outerpos(3) - ti(1) - ti(3);
ax_height = outerpos(4) - ti(2) - ti(4);
ax.Position = [left*1.1 bottom ax_width*.98 ax_height*1.1];

set(gcf, 'Position', [100, 100, 500, 290])
%title('Cone beam experiments')
saveas(gcf,'cone_plot.png')

%%
close all; clear all;
load('cone_beam_images.mat')
x_ncs_img = zeros(420+96,420+96);
x_ncs_img(1:420,1:420) = x_ncs(:,:,66);
x_ncs_img(1:420,421:(420+96)) = squeeze(x_ncs(:,210,:));
x_ncs_img(421:(420+96),1:420) = squeeze(x_ncs(210,:,:))';
x_ncs_img = x_ncs_img/1.7e+03;

x_pdhg_img = zeros(420+96,420+96);
x_pdhg_img(1:420,1:420) = x_pdhg(:,:,66);
x_pdhg_img(1:420,421:(420+96)) = squeeze(x_pdhg(:,210,:));
x_pdhg_img(421:(420+96),1:420) = squeeze(x_pdhg(210,:,:))';
x_pdhg_img = x_pdhg_img/1.7e+03;


x_admm_img = zeros(420+96,420+96);
x_admm_img(1:420,1:420) = x_admm(:,:,66);
x_admm_img(1:420,421:(420+96)) = squeeze(x_admm(:,210,:));
x_admm_img(421:(420+96),1:420) = squeeze(x_admm(210,:,:))';
x_admm_img = x_admm_img/1.7e+03;


figure
subplot(1,3,1)
imshow(x_ncs_img)
title('Cone beam (NCS)')
subplot(1,3,2)
imshow(x_pdhg_img)
title('Cone beam (PDHG)')
subplot(1,3,3)
imshow(x_admm_img)
title('Cone beam (ADMM)')

set(gcf, 'Position', [100, 100, 800, 300])

imwrite(x_ncs_img, 'cone_beam_ncs.png');
imwrite(x_pdhg_img, 'cone_beam_pdhg.png');
imwrite(x_admm_img, 'cone_beam_admm.png');


%%
function [x, kk] = cgsolve(xin, b, N, M, A, mask, beta, precond)
  x = xin;
  r = b - compute_Gx(x, N, M, A, mask, beta);
  
  p = real(ifftn(precond .* fftn(r)));
  z = p;
  rtz = sum(sum(sum(r .* z)));
  for kk = 1:10
    Gp = compute_Gx(p, N, M, A, mask, beta);
    alpha = rtz / sum(sum(sum(p .* Gp)));
    x = x + alpha * p;
    r = r - alpha * Gp;
    rsnew = sum(sum(sum(r .^ 2)));

    z = real(ifftn(precond .* fftn(r)));

    rtzold = rtz;
    rtz = sum(sum(sum(r .* z)));
    beta = rtz / rtzold;
    p = z + beta * p;
      end
end

function Gx = compute_Gx(x, N, M, A, mask, beta)
  [Dxx, Dxy, Dxz] = compute_Dx(x, N, M);
  Gx = embed(A' * (A * x(mask(:))), mask) + beta * compute_Dpv(Dxx, Dxy, Dxz, N, M);
end

function [Dxx, Dxy, Dxz] = compute_Dx(x, N, M)
  Dxx = zeros(N, N, M);
  Dxy = zeros(N, N, M);
  Dxz = zeros(N, N, M);
  Dxx(1:N, 1:(N-1), 1:M) = x(1:N, 1:(N-1), 1:M) - x(1:N, 2:N, 1:M);
  Dxy(1:(N-1), 1:N, 1:M) = x(1:(N-1), 1:N, 1:M) - x(2:N, 1:N, 1:M);
  Dxz(1:N, 1:N, 1:(M-1)) = x(1:N, 1:N, 1:(M-1)) - x(1:N, 1:N, 2:M);
end

function Dpv = compute_Dpv(vx, vy, vz, N, M)
  Dpv = vx + vy + vz;
    Dpv(1:N,2:N,1:M) = Dpv(1:N,2:N,1:M) - vx(1:N,1:(N-1),1:M);
    Dpv(2:N,1:N,1:M) = Dpv(2:N,1:N,1:M) - vy(1:(N-1),1:N,1:M);
    Dpv(1:N,1:N,2:M) = Dpv(1:N,1:N,2:M) - vz(1:N,1:N,1:(M-1)); 
end
%}