close all
clear all
clc

%% Define dimensions
r_base = 0.402;             % radius of platform, in m
r_platform = 0.265;         % radius of base, in m
shortleg = 0.16;            % length of motor arm, in m
longleg = 1;                % length of connecting rod, in m
z0_platform = 1;            % rest height of platform
m = 340/2.2;                % mass of platform   (from Inventor model)
J = [15.63, 35.35, 40.50];  % inertia, kg-m^2    (from Inventor model)

%% Read in raw data
rawdata=csvread('2015-01-24_11-49-26.csv');   % roundabout data file
time1 = rawdata(:,2);

% actual angle, called "MotionRoll/Pitch/Yaw" in data --> checked by
%   inspection of plot_roundabout_data.m
%   --> raw values in radians
angle_x=rawdata(:,26);%CHECK THESE COLUMN ORDERS!!!
angle_y=rawdata(:,25);
angle_z=rawdata(:,24);
angle=[angle_x, angle_y, angle_z];

% linear acceleration, called "AccelerationX/Y/Z" in data
%   --> raw values in g's, want to convert to m/s^2
acc_x=rawdata(:,13).*9.81;
acc_y=rawdata(:,12).*9.81;%THESE DIRECTIONS ARE OUT OF ORDER. WEIRD
acc_z=rawdata(:,14).*9.81;%NOW THESE ARE IN M/S/S SO MAKE SURE SIM IS TOO!
accel=[acc_x, acc_y, acc_z+9.81];%added g to z to offset gravity. This is meh....

% compose signals for simulink
signal_x=[time1,accel(:,1)];
signal_y=[time1,accel(:,2)];
signal_z=[time1,accel(:,3)];

figure()
subplot(3,1,1)
plot(signal_x(:,1),signal_x(:,2))
ylabel('ax')
subplot(3,1,2)
plot(signal_y(:,1),signal_y(:,2))
ylabel('ay')
subplot(3,1,3)
plot(signal_z(:,1),signal_z(:,2))
xlabel('Time (s)')
ylabel('az')
%% Run simulink motion cueing algorithm
%   --> output is axtilt, aytilt, xdesired, ydesired, zdesired
sim('demostration1.slx');
motion_des = [xdesired, ydesired, zdesired];
angle_x = interp1(time1, angle(:,1), simtime);
angle_y = interp1(time1, angle(:,2), simtime);
angle_z = interp1(time1, angle(:,3), simtime);
%angle_x= angle_x(~isnan(angle_x));
%angle_y= angle_y(~isnan(angle_y));

%angle_des = [angle_x(3:end)+axtilt, angle_y(3:end)+aytilt, angle_z(6:end)]; %% had to do stupid things to trim vectors, should fix this later %%
angle_des = [angle_x+axtilt, angle_y+aytilt, zeros(size(angle_z))]; %% had to do stupid things to trim vectors, should fix this later %%
%MEGAN-- WE NEED TO FIX THE ANGLE Z. We can't ask for angle z directly...
%needs to be high pass filtered!!! Grab this from Dallis's branch and paste
%into your simulink??
%% Run loop to determine platform position, motor arm angles, motor torques
% notation:
%       P = connection point between connecting rod and platform
%       Q = connection point between motor arm and connecting rod
%       O = connection point between motor arm and base
%       G = 0,0,0 (ground)
R_po = zeros(6,3);
R_pq = zeros(6,3);
R_qo = zeros(6,3);
F_pq = zeros(6,3);
Torque = zeros(6,3);
motor_angle = zeros(6,3);
initial = 0;        %   -->  what is this??
opt = zeros(6,1);
x = zeros(6,1);
y = zeros(6,1);
z = zeros(6,1);
error = zeros(6,1);
w_x = zeros(6,1);
w_y = zeros(6,1);
w_z = zeros(6,1);       % angular velocity of motor arms
alpha_x = zeros(6,1);
alpha_y = zeros(6,1);
alpha_z = zeros(6,1);       % angular acc of motor arms
T = zeros(6,1);
T_qo = zeros(6,3);
Rpq_x = zeros(6,1);
Rpq_y = zeros(6,1);
Rpq_z = zeros(6,1);
Rqo_x = zeros(6,1);
Rqo_y = zeros(6,1);
Rqo_z = zeros(6,1);
T_qo_x = zeros(6,1);
T_qo_y = zeros(6,1);
T_qo_z = zeros(6,1);
torque = [];
angVel_x = [];
angVel_y = [];
angVel_z = [];
angAcc_x = [];
angAcc_y = [];
angAcc_z = [];
om = [];

%plot the desired angles
figure()
plot(simtime,angle_des(:,1),simtime,angle_des(:,2),simtime,angle_des(:,3))
xlabel('Time (s)')
ylabel('Desired angles')
legend('x','y','z')

figure()
plot(simtime,motion_des(:,1),simtime,motion_des(:,2),simtime,motion_des(:,3))
xlabel('Time (s)')
ylabel('Desired motion')
legend('x','y','z')

pause


%create a matrix to store torques for each motor
Motor_Torques = zeros(length(simtime),6);%done
Motor_angular_vels = zeros(length(simtime),6);%todo store this way
Motor_angular_accels = zeros(length(simtime),6);%todo store this way


for i=1:length(motion_des)    % motion index
    % solve for platform position and "leg" length, pause to see plot
    % (maybe)
    [R_po, motors, platform_points, motorangles, R_pc] = platformposition(motion_des(i,:),angle_des(i,:), r_base, r_platform, z0_platform);
    
    cla()
    % plot it!
    hold on
    grid on
    platformX = [platform_points(1,1),platform_points(2,1),platform_points(3,1),platform_points(1,1)];
    platformY = [platform_points(1,2),platform_points(2,2),platform_points(3,2),platform_points(1,2)];
    platformZ = [platform_points(1,3),platform_points(2,3),platform_points(3,3),platform_points(1,3)];
    baseX = [motors(1,1),motors(2,1),motors(3,1),motors(4,1),motors(5,1),motors(6,1),motors(1,1)];
    baseY = [motors(1,2),motors(2,2),motors(3,2),motors(4,2),motors(5,2),motors(6,2),motors(1,2)];
    baseZ = [motors(1,3),motors(2,3),motors(3,3),motors(4,3),motors(5,3),motors(6,3),motors(1,3)];
    
    if i>1
        w_x=(angle_x(i)-angle_x(i-1))/0.05;
        w_y=(angle_y(i)-angle_y(i-1))/0.05;
        w_z=0;
    else
        w_x=0;
        w_y=0;
        w_z=0;
    end
    
    angVel_x = [angVel_x,w_x]; % write old variables
    angVel_y = [angVel_y,w_y];
    angVel_z = [angVel_z,w_z];
    
    if i>2
        alpha_x=(angVel_x(i-1)-angVel_x(i-2))/0.05;
        alpha_y=(angVel_y(i-1)-angVel_y(i-2))/0.05;
        alpha_z=0;
    else
        alpha_x=0;
        alpha_y=0;
        alpha_z=0;
    end
    
    angAcc_x = [angAcc_x,alpha_x]; % write old variables
    angAcc_y = [angAcc_y,alpha_y];
    angAcc_z = [angAcc_z,alpha_z];
    
    alpha = [alpha_x, alpha_y, alpha_z]/180*pi; %%%%%%%%%%%%%%
    
    % find angles for motor arms using fminsearch
    for j = 1:6             % leg index
        %find this motor angle
        angle = @ (parm) findpq_leg(R_po(j,:), shortleg, longleg, motorangles(j), parm);
        [opt(i,j)] = fminsearch(angle, initial);
        [error, x, y, z] = angle(opt(i,j));
        R_pq = [x, y, z];
        R_qo = R_po(j,:) - R_pq;
        Rpq_x(j) = R_pq(1);     % had to disassemble R_pq so that it would write to j
        Rpq_y(j) = R_pq(2);
        Rpq_z(j) = R_pq(3);
        Rqo_x(j) = R_qo(1);
        Rqo_y(j) = R_qo(2);
        Rqo_z(j) = R_qo(3);
    end
    
    R_pq = [Rpq_x, Rpq_y, Rpq_z];       % reassemble
    R_qo = [Rqo_x, Rqo_y, Rqo_z]; 
    R_pg = platform_points;%calculate global location of points P. just call it the right thing... not used at the moment.
    
    % find force, torque on each leg
    for k = 1:6
        [F_pq] = forceplatform(m, J, R_pq(1,:), R_pq(2,:), R_pq(3,:), R_pq(4,:), R_pq(5,:), R_pq(6,:), R_pc(1,:), R_pc(2,:), R_pc(3,:), motion_des(i,:), alpha);
        
        for m = 1:6
            T_qo = cross(R_qo(m,:), -F_pq(m,:));
            T_qo_x(m) = T_qo(1);     % had to disassemble R_pq so that it would write to j
            T_qo_y(m) = T_qo(2);
            T_qo_z(m) = T_qo(3);
        end
        
        T_qo = [T_qo_x, T_qo_y, T_qo_z];    % reassemble
      T(k) = norm(T_qo);
      %store this in the matrix...
      Motor_Torques(i,k) = norm(T_qo);%eventually delete the line above. TODO dot product.
        
%         e_motorX = cos(motorangles');
%         e_motorY = sin(motorangles');
%         e_motorZ = zeros(1,6);
%         e_motor = [e_motorX, e_motorY, e_motorZ]; %%%this needs fixing
%         T(k) = dot(e_motor(k,:), T_qo(k,:));
    end

    torque = [torque; T];
    
    % just for plotting
    motorarm1X = [motors(1,1), R_qo(1,1)+motors(1,1)];
    motorarm2X = [motors(2,1), R_qo(2,1)+motors(2,1)];
    motorarm3X = [motors(3,1), R_qo(3,1)+motors(3,1)];
    motorarm4X = [motors(4,1), R_qo(4,1)+motors(4,1)];
    motorarm5X = [motors(5,1), R_qo(5,1)+motors(5,1)];
    motorarm6X = [motors(6,1), R_qo(6,1)+motors(6,1)];
    
    motorarm1Y = [motors(1,2), R_qo(1,2)+motors(1,2)];
    motorarm2Y = [motors(2,2), R_qo(2,2)+motors(2,2)];
    motorarm3Y = [motors(3,2), R_qo(3,2)+motors(3,2)];
    motorarm4Y = [motors(4,2), R_qo(4,2)+motors(4,2)];
    motorarm5Y = [motors(5,2), R_qo(5,2)+motors(5,2)];
    motorarm6Y = [motors(6,2), R_qo(6,2)+motors(6,2)];
    
    motorarm1Z = [motors(1,3), R_qo(1,3)+motors(1,3)];
    motorarm2Z = [motors(2,3), R_qo(2,3)+motors(2,3)];
    motorarm3Z = [motors(3,3), R_qo(3,3)+motors(3,3)];
    motorarm4Z = [motors(4,3), R_qo(4,3)+motors(4,3)];
    motorarm5Z = [motors(5,3), R_qo(5,3)+motors(5,3)];
    motorarm6Z = [motors(6,3), R_qo(6,3)+motors(6,3)];
    
    motorarm1X = [motors(1,1), R_qo(1,1)+motors(1,1)];
    motorarm2X = [motors(2,1), R_qo(2,1)+motors(2,1)];
    motorarm3X = [motors(3,1), R_qo(3,1)+motors(3,1)];
    motorarm4X = [motors(4,1), R_qo(4,1)+motors(4,1)];
    motorarm5X = [motors(5,1), R_qo(5,1)+motors(5,1)];
    motorarm6X = [motors(6,1), R_qo(6,1)+motors(6,1)];
    
    motorarm1Y = [motors(1,2), R_qo(1,2)+motors(1,2)];
    motorarm2Y = [motors(2,2), R_qo(2,2)+motors(2,2)];
    motorarm3Y = [motors(3,2), R_qo(3,2)+motors(3,2)];
    motorarm4Y = [motors(4,2), R_qo(4,2)+motors(4,2)];
    motorarm5Y = [motors(5,2), R_qo(5,2)+motors(5,2)];
    motorarm6Y = [motors(6,2), R_qo(6,2)+motors(6,2)];
    
    motorarm1Z = [motors(1,3), R_qo(1,3)+motors(1,3)];
    motorarm2Z = [motors(2,3), R_qo(2,3)+motors(2,3)];
    motorarm3Z = [motors(3,3), R_qo(3,3)+motors(3,3)];
    motorarm4Z = [motors(4,3), R_qo(4,3)+motors(4,3)];
    motorarm5Z = [motors(5,3), R_qo(5,3)+motors(5,3)];
    motorarm6Z = [motors(6,3), R_qo(6,3)+motors(6,3)];
    
    
    plot3(motorarm1X, motorarm1Y, motorarm1Z);
    plot3(motorarm2X, motorarm2Y, motorarm2Z);
    plot3(motorarm3X, motorarm3Y, motorarm3Z);
    plot3(motorarm4X, motorarm4Y, motorarm4Z);
    plot3(motorarm5X, motorarm5Y, motorarm5Z);
    plot3(motorarm6X, motorarm6Y, motorarm6Z);
    plot3(platformX, platformY, platformZ);
    plot3(baseX, baseY, baseZ)
    view(-205,45)
    pause(0.01)

%     h_old = h;
%     delete(h_old);
%     drawnow
end
hold off

% calculate angular velocity
omega = zeros(size(torque));

for n = 1:6
    opt_new = opt(:,n);               % split angle matrix into columns
    for i=1:length(motion_des)        % motion index
        if i>1
            omega(i)= (opt(i)-opt(i-1))/.05;
        else
            omega(i) = 0;
        end
    end
    om = [om; omega];                 % save old vars
end

%plot motor angles
figure()
plot(simtime,opt(:,1),simtime,opt(:,2),simtime,opt(:,3),simtime,opt(:,4),simtime,opt(:,5),simtime,opt(:,6))
hold on
plot([min(simtime) max(simtime)],[0,0],'r','LineWidth',4)
plot([min(simtime) max(simtime)],[pi/4,pi/4],'r','LineWidth',4)
legend('motor 1','motor 2','motor 3','motor 4','motor 5','motor 6','motor limits')
xlabel('Time (s)')
ylabel('motor arm angle requested (rad)')

figure()
plot(abs(om(1:13734)),torque)
xlim([0, 2])
ylim([0, 1000])
xlabel 'omega'
ylabel 'torque'




