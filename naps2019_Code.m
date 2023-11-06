clear all
close all
clc

H = 24;%Planning Horizon
Nag = 4;%# of agents in MG
time=linspace(1,H,H);
t0=1;
t1=9;
t2=23;
data_import=importdata('imported_data.mat');
Loaddata=data_import.FeederFiles;
PVdata=data_import.PVdatas;
%%
%------------------------------------------------------------------------
%MG initialization
%------------------------------------------------------------------------

%DG
P_DG = zeros(1,H);
P_DG_max=10;
P_DG_min=0;

%ESS
E0=30;
SOC_max=0.9;
ESS_max=SOC_max*E0;
SOC_min=0.25;
ESS_min=SOC_min*E0;
P_ESS_max=5;
P_ESS=zeros(1,H);
SOC=zeros(1,H);
E_ESS = zeros(1,H);
E_ESS(1)=ESS_min;
SOC(1)=E_ESS(1)/E0;

%PV
PV_imported = PVdata(1:H);
PV=PV_imported.*(0.5.*P_DG_max/max(PV_imported));

%Load
L_import=Loaddata(1:H); % only keep data for a day
load = (2.9*P_DG_max/max(L_import)).*L_import;
critical_load=(1/2.5).*load; % considers 40% of the total load is critical load
controllable_load=load-critical_load;
non_critical_load=zeros(3,H); % curtailment will happen in 3 stages
non_critical_load(1,:)=0.2.*controllable_load;
non_critical_load(2,:)=0.3.*controllable_load;
non_critical_load(3,:)=controllable_load-(non_critical_load(1,:)+non_critical_load(2,:));
n_c1=non_critical_load(1,:);
n_c2=non_critical_load(2,:);
n_c3=non_critical_load(3,:);

% save('load_profile.mat','load','critical_load','n_c1','n_c2','n_c3')
clear n_c1 n_c2 n_c3;

%DR
DR=zeros(1,H);

%Grid
PG = zeros(1,H);

clear data_import Loaddata PVdata;
%%

%probability
probability=zeros(1,H);
probability(t0:t0+1)=0.1;
probability(t0+2:(t1-1))=0.7;
probability((t2+1):H)=0.1;
probability(t1:t2)=0.99;

%power deficiency
d1=zeros(1,H);
d2=zeros(1,H);
d3=zeros(1,H);

%%

for t=1:H
    
    %check probability
    if probability(t)<=min(probability)
        
        %ESS
        %constraint
        if E_ESS(t)<ESS_min
            E_ESS(t)=ESS_min;
        elseif E_ESS(t)>ESS_max
            E_ESS(t)=ESS_max;
        end
        SOC(t)=SOC_min;
        
        %Grid
        PG(t)=(load(t)+abs(P_ESS(t)))-PV(t);
        
        %before event
    elseif probability(t)>min(probability) && probability(t)<max(probability)
        if t>1
            %ESS
            
            %constraint
            if E_ESS(t-1)<ESS_min
                E_ESS(t)=ESS_min;
            elseif E_ESS(t-1)>ESS_max
                E_ESS(t)=ESS_max;
            else
                E_ESS(t)=E_ESS(t-1);
            end
            
            %charging
            if (ESS_max-E_ESS(t-1))>P_ESS_max
                E_ESS(t)=E_ESS(t-1)+P_ESS_max;
            else
                E_ESS(t)=E_ESS(t-1)+(ESS_max-E_ESS(t-1));
            end
            P_ESS(t)=E_ESS(t)-E_ESS(t-1);
            SOC(t)=SOC(t-1)-(P_ESS(t)/ESS_max);
        end
        
        %Grid
        PG(t)=(load(t)+abs(P_ESS(t)))-PV(t);
    else
        %during event
        
        %Grid
        PG(t)=0;
        
        %DG
        d1(t)=load(t)-(PV(t)+PG(t));
        if (d1(t))<P_DG_max
            P_DG(t)=d1(t);
        else
            P_DG(t)=P_DG_max;
        end
        d2(t)=d1(t)-P_DG(t);       
        
    end
    
end

%ESS
weighted_deficit=zeros(1,H);
sum_d2=sum(d2);
for t=1:H
    if probability(t)==max(probability)
        weighted_deficit(t)=d2(t)/sum_d2;
        P_ESS(t)=(-(ESS_max-ESS_min)*weighted_deficit(t));
        %charge constraint
        if abs(P_ESS(t))>P_ESS_max 
            P_ESS(t)=-P_ESS_max;
        end
        %constraint
        if (E_ESS(t-1)+P_ESS(t))>ESS_min
            E_ESS(t)=E_ESS(t-1)+P_ESS(t);
        else
            E_ESS(t)=ESS_min;
            P_ESS(t)=E_ESS(t)-E_ESS(t-1);
        end
    end
end

%total deficit
d3(t1:t2)=d2(t1:t2)-abs(P_ESS(t1:t2));


%%

demand=zeros(1,H);
supply=zeros(1,H);

for t=1:H
     if P_ESS(t)>0
        demand(t)=load(t)+abs(P_ESS(t))+0.25; %0.25 is to avoid overlap
        supply(t)=PG(t)+PV(t)+P_DG(t);
    else
        demand(t)=load(t)+0.25;
        supply(t)=PG(t)+PV(t)+P_DG(t)+abs(P_ESS(t));
    end
end

%DR
DR(t1:t2)=d3(t1:t2);
% save('loadcurtailmentcolution.mat','E_ESS','DR','probability')

%%
figure(1)
plot(demand,':','LineWidth',2)
hold on
plot(critical_load,'--','LineWidth',2)
hold on
plot(supply,'LineWidth',2)
hold off
xlim([1 H])
ylim([0 (max(demand)+2)])
% xlim([12 22])
xlabel('Time (hours)')
ylabel('Power (MW)')
legend('Total Demand','Critical Load','Total Supply')
%%
figure(2)
plot(probability,'LineWidth',2)

xlim([1 H])
ylim([0 (max(probability)+.2)])
% xlim([12 22])
xlabel('Time (hours)')
ylabel(' ')
legend('Probability of Extreme Event')

figure(3)
plot(E_ESS,'LineWidth',2)
xlim([1 H])
ylim([0 max(E_ESS)+2])
legend('Energy of ESS')
xlabel('Time(hours)')