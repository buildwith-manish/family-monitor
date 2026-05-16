import { db } from '@/lib/db';
import { NextResponse } from 'next/server';

export async function GET() {
  try {
    const family = await db.family.findFirst({
      include: {
        members: {
          include: {
            devices: {
              include: {
                screenTime: { orderBy: { date: 'desc' }, take: 7 },
                appUsage: { orderBy: { date: 'desc' }, take: 20 },
                location: { orderBy: { timestamp: 'desc' }, take: 5 },
              },
            },
          },
          orderBy: { createdAt: 'asc' },
        },
      },
    });

    if (!family) {
      return NextResponse.json({ error: 'No family found. Please seed the database first.' }, { status: 404 });
    }

    return NextResponse.json(family);
  } catch (error) {
    console.error('Family GET error:', error);
    return NextResponse.json({ error: 'Failed to fetch family data' }, { status: 500 });
  }
}

export async function POST(request: Request) {
  try {
    const body = await request.json();
    const { name, email, role, avatar, familyId } = body;

    if (!name || !familyId) {
      return NextResponse.json({ error: 'Name and familyId are required' }, { status: 400 });
    }

    const member = await db.member.create({
      data: {
        name,
        email: email || null,
        role: role || 'child',
        avatar: avatar || null,
        familyId,
      },
    });

    return NextResponse.json(member);
  } catch (error) {
    console.error('Family POST error:', error);
    return NextResponse.json({ error: 'Failed to add family member' }, { status: 500 });
  }
}
