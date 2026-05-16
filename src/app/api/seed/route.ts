import { db } from '@/lib/db';
import { NextResponse } from 'next/server';

export async function GET() {
  try {
    // Check if data already exists
    const existingFamily = await db.family.findFirst();
    if (existingFamily) {
      return NextResponse.json({ message: 'Data already seeded', family: existingFamily });
    }

    // Create family
    const family = await db.family.create({
      data: {
        name: 'Sharma Family',
        code: 'SHRM2024',
      },
    });

    // Create members
    const rajesh = await db.member.create({
      data: {
        name: 'Rajesh Sharma',
        email: 'rajesh@sharma.com',
        role: 'parent',
        avatar: '👨',
        familyId: family.id,
      },
    });

    const priya = await db.member.create({
      data: {
        name: 'Priya Sharma',
        email: 'priya@sharma.com',
        role: 'parent',
        avatar: '👩',
        familyId: family.id,
      },
    });

    const aarav = await db.member.create({
      data: {
        name: 'Aarav Sharma',
        email: 'aarav@sharma.com',
        role: 'child',
        avatar: '👦',
        familyId: family.id,
      },
    });

    const diya = await db.member.create({
      data: {
        name: 'Diya Sharma',
        email: 'diya@sharma.com',
        role: 'child',
        avatar: '👧',
        familyId: family.id,
      },
    });

    const vivaan = await db.member.create({
      data: {
        name: 'Vivaan Sharma',
        email: 'vivaan@sharma.com',
        role: 'child',
        avatar: '🧒',
        familyId: family.id,
      },
    });

    // Create devices
    const aaravPhone = await db.device.create({
      data: {
        name: "Aarav's iPhone",
        type: 'smartphone',
        os: 'iOS 17',
        model: 'iPhone 15',
        status: 'online',
        batteryLevel: 72,
        lastSeen: new Date(),
        memberId: aarav.id,
      },
    });

    const aaravTablet = await db.device.create({
      data: {
        name: "Aarav's iPad",
        type: 'tablet',
        os: 'iPadOS 17',
        model: 'iPad Air',
        status: 'offline',
        batteryLevel: 15,
        lastSeen: new Date(Date.now() - 3600000 * 3),
        memberId: aarav.id,
      },
    });

    const diyaPhone = await db.device.create({
      data: {
        name: "Diya's Samsung",
        type: 'smartphone',
        os: 'Android 14',
        model: 'Samsung Galaxy A54',
        status: 'online',
        batteryLevel: 89,
        lastSeen: new Date(),
        memberId: diya.id,
      },
    });

    const diyaTablet = await db.device.create({
      data: {
        name: "Diya's Tablet",
        type: 'tablet',
        os: 'Android 13',
        model: 'Samsung Tab A9',
        status: 'online',
        batteryLevel: 56,
        lastSeen: new Date(),
        memberId: diya.id,
      },
    });

    const vivaanTablet = await db.device.create({
      data: {
        name: "Vivaan's iPad",
        type: 'tablet',
        os: 'iPadOS 16',
        model: 'iPad Mini',
        status: 'online',
        batteryLevel: 43,
        lastSeen: new Date(),
        memberId: vivaan.id,
      },
    });

    const rajeshPhone = await db.device.create({
      data: {
        name: "Rajesh's iPhone",
        type: 'smartphone',
        os: 'iOS 17',
        model: 'iPhone 15 Pro',
        status: 'online',
        batteryLevel: 65,
        lastSeen: new Date(),
        memberId: rajesh.id,
      },
    });

    const allDevices = [aaravPhone, aaravTablet, diyaPhone, diyaTablet, vivaanTablet, rajeshPhone];

    // Create screen time data (7 days)
    for (const device of allDevices) {
      for (let i = 6; i >= 0; i--) {
        const date = new Date();
        date.setDate(date.getDate() - i);
        date.setHours(0, 0, 0, 0);

        const baseMinutes = device.memberId === rajesh.id ? 45 : device.memberId === priya.id ? 30 : 0;
        const childBase = Math.floor(Math.random() * 120) + 60;
        const totalMinutes = baseMinutes || childBase;
        const limitMinutes = device.memberId === rajesh.id ? null : 120;

        await db.screenTime.create({
          data: {
            date,
            totalMinutes,
            limitMinutes,
            deviceId: device.id,
          },
        });
      }
    }

    // Create app usage data
    const apps = [
      { name: 'WhatsApp', category: 'social', mins: [45, 60, 30, 55, 40, 70, 35] },
      { name: 'YouTube', category: 'entertainment', mins: [90, 120, 60, 80, 100, 110, 75] },
      { name: 'Instagram', category: 'social', mins: [30, 45, 25, 50, 35, 40, 20] },
      { name: 'Minecraft', category: 'games', mins: [60, 90, 45, 75, 55, 80, 30] },
      { name: 'Khan Academy', category: 'education', mins: [30, 25, 40, 35, 20, 30, 45] },
      { name: 'Roblox', category: 'games', mins: [40, 55, 30, 60, 45, 50, 25] },
      { name: 'TikTok', category: 'social', mins: [35, 50, 20, 40, 55, 45, 30] },
      { name: 'Chrome', category: 'productivity', mins: [20, 15, 25, 10, 30, 20, 15] },
      { name: 'Netflix', category: 'entertainment', mins: [50, 70, 40, 60, 45, 80, 55] },
      { name: 'Duolingo', category: 'education', mins: [15, 20, 10, 25, 15, 20, 10] },
    ];

    // Only create app usage for child devices and rajesh
    const childDevices = [aaravPhone, aaravTablet, diyaPhone, diyaTablet, vivaanTablet];
    for (const device of childDevices) {
      for (const app of apps) {
        for (let i = 6; i >= 0; i--) {
          const date = new Date();
          date.setDate(date.getDate() - i);
          date.setHours(0, 0, 0, 0);

          const usageMinutes = app.mins[6 - i] + Math.floor(Math.random() * 20) - 10;

          await db.appUsage.create({
            data: {
              appName: app.name,
              category: app.category,
              usageMinutes: Math.max(5, usageMinutes),
              date,
              deviceId: device.id,
            },
          });
        }
      }
    }

    // Create location history
    const locations = [
      { lat: 28.6139, lng: 77.2090, address: 'India Gate, New Delhi' },
      { lat: 28.5355, lng: 77.3910, address: 'Sector 18, Noida' },
      { lat: 28.4595, lng: 77.0266, address: 'DLF Cyber City, Gurgaon' },
      { lat: 28.6327, lng: 77.2195, address: 'Connaught Place, New Delhi' },
      { lat: 28.5504, lng: 77.2493, address: 'Saket, New Delhi' },
      { lat: 28.6280, lng: 77.2168, address: 'Jantar Mantar, New Delhi' },
      { lat: 28.5921, lng: 77.2494, address: 'Khan Market, New Delhi' },
      { lat: 28.6127, lng: 77.2295, address: 'Rajpath, New Delhi' },
    ];

    for (const device of childDevices) {
      for (let i = 0; i < 5; i++) {
        const loc = locations[Math.floor(Math.random() * locations.length)];
        const timestamp = new Date(Date.now() - Math.random() * 86400000 * 3);

        await db.location.create({
          data: {
            latitude: loc.lat + (Math.random() - 0.5) * 0.01,
            longitude: loc.lng + (Math.random() - 0.5) * 0.01,
            address: loc.address,
            timestamp,
            deviceId: device.id,
          },
        });
      }
    }

    // Create alerts
    const alerts = [
      { type: 'geofence', severity: 'warning', title: 'Geofence Alert', message: 'Aarav left the designated safe zone near school', memberId: aarav.id, deviceId: aaravPhone.id },
      { type: 'screen_time', severity: 'critical', title: 'Screen Time Exceeded', message: 'Diya has exceeded daily screen time limit by 45 minutes', memberId: diya.id, deviceId: diyaPhone.id },
      { type: 'app_install', severity: 'info', title: 'New App Installed', message: 'Vivaan installed TikTok on his iPad', memberId: vivaan.id, deviceId: vivaanTablet.id },
      { type: 'content_access', severity: 'critical', title: 'Blocked Content Access', message: 'Aarav attempted to access adult content on YouTube', memberId: aarav.id, deviceId: aaravPhone.id },
      { type: 'sos', severity: 'critical', title: 'SOS Alert', message: 'Diya triggered SOS alert from school area', memberId: diya.id, deviceId: diyaPhone.id },
      { type: 'screen_time', severity: 'warning', title: 'Screen Time Warning', message: 'Aarav is approaching daily screen time limit', memberId: aarav.id, deviceId: aaravPhone.id },
      { type: 'geofence', severity: 'info', title: 'Location Update', message: 'Vivaan arrived at home zone', memberId: vivaan.id, deviceId: vivaanTablet.id },
      { type: 'app_install', severity: 'warning', title: 'Game App Detected', message: 'Diya installed Roblox without permission', memberId: diya.id, deviceId: diyaPhone.id },
      { type: 'content_access', severity: 'warning', title: 'Social Media Access', message: 'Aarav accessed Instagram during study time', memberId: aarav.id, deviceId: aaravPhone.id },
      { type: 'screen_time', severity: 'info', title: 'Screen Time Report', message: 'Weekly screen time report is ready for review', memberId: null, deviceId: null },
      { type: 'geofence', severity: 'warning', title: 'Late Return', message: 'Aarav has not returned from school on time', memberId: aarav.id, deviceId: aaravPhone.id },
      { type: 'sos', severity: 'critical', title: 'Emergency Alert', message: 'Unknown SOS signal detected from Diya\'s device', memberId: diya.id, deviceId: diyaPhone.id },
    ];

    for (const alert of alerts) {
      const createdAt = new Date(Date.now() - Math.random() * 86400000 * 7);
      await db.alert.create({
        data: {
          type: alert.type,
          severity: alert.severity,
          title: alert.title,
          message: alert.message,
          read: Math.random() > 0.6,
          memberId: alert.memberId,
          deviceId: alert.deviceId,
          createdAt,
        },
      });
    }

    // Create content filters for all child devices
    const filterCategories = ['violence', 'adult', 'gambling', 'social', 'games'];
    for (const device of childDevices) {
      for (const category of filterCategories) {
        await db.contentFilter.create({
          data: {
            category,
            enabled: category !== 'social',
            blockLevel: category === 'adult' ? 'high' : category === 'violence' ? 'high' : 'medium',
            deviceId: device.id,
          },
        });
      }
    }

    // Create schedule rules
    await db.scheduleRule.create({
      data: {
        name: 'Bedtime',
        type: 'bedtime',
        startHour: 21,
        startMinute: 0,
        endHour: 7,
        endMinute: 0,
        daysOfWeek: '1,2,3,4,5,6,7',
        allowApps: '',
        deviceId: aaravPhone.id,
        enabled: true,
      },
    });

    await db.scheduleRule.create({
      data: {
        name: 'Study Time',
        type: 'study_time',
        startHour: 16,
        startMinute: 0,
        endHour: 18,
        endMinute: 0,
        daysOfWeek: '1,2,3,4,5',
        allowApps: 'Khan Academy,Duolingo,Chrome',
        deviceId: aaravPhone.id,
        enabled: true,
      },
    });

    await db.scheduleRule.create({
      data: {
        name: 'Free Time',
        type: 'free_time',
        startHour: 18,
        startMinute: 0,
        endHour: 21,
        endMinute: 0,
        daysOfWeek: '1,2,3,4,5',
        allowApps: '',
        deviceId: aaravPhone.id,
        enabled: true,
      },
    });

    await db.scheduleRule.create({
      data: {
        name: 'Diya Bedtime',
        type: 'bedtime',
        startHour: 20,
        startMinute: 0,
        endHour: 7,
        endMinute: 0,
        daysOfWeek: '1,2,3,4,5,6,7',
        allowApps: '',
        deviceId: diyaPhone.id,
        enabled: true,
      },
    });

    await db.scheduleRule.create({
      data: {
        name: 'Diya Study Time',
        type: 'study_time',
        startHour: 15,
        startMinute: 0,
        endHour: 17,
        endMinute: 0,
        daysOfWeek: '1,2,3,4,5',
        allowApps: 'Khan Academy,Duolingo',
        deviceId: diyaPhone.id,
        enabled: true,
      },
    });

    await db.scheduleRule.create({
      data: {
        name: 'Vivaan Bedtime',
        type: 'bedtime',
        startHour: 19,
        startMinute: 30,
        endHour: 7,
        endMinute: 0,
        daysOfWeek: '1,2,3,4,5,6,7',
        allowApps: '',
        deviceId: vivaanTablet.id,
        enabled: true,
      },
    });

    return NextResponse.json({ message: 'Database seeded successfully', familyId: family.id });
  } catch (error) {
    console.error('Seed error:', error);
    return NextResponse.json({ error: 'Failed to seed database' }, { status: 500 });
  }
}
